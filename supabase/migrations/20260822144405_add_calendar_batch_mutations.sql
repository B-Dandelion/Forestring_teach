-- Calendar batch mutations.
-- Root cause:
-- adjacent semester boundaries often must move together, while single-row
-- mutations validate contiguity too early.

create or replace function public.apply_semester_calendar_batch(
  p_changes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_item jsonb;
  v_semester_id uuid;
  v_code text;
  v_starts_on date;
  v_ends_on date;

  v_existing public.semesters%rowtype;

  v_changed_ids uuid[] := array[]::uuid[];
  v_changed_count integer := 0;

  v_stage_base date;
  v_stage_index integer := 0;

  v_branch record;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    null,
    true
  ) a;

  if p_changes is null
     or jsonb_typeof(p_changes) <> 'array'
     or jsonb_array_length(p_changes) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_BATCH_REQUIRED';
  end if;

  if exists (
    select 1
    from (
      select
        value ->> 'semesterId' as semester_id_text,
        count(*) as item_count
      from jsonb_array_elements(p_changes)
      group by value ->> 'semesterId'
    ) duplicate
    where duplicate.semester_id_text is null
       or duplicate.semester_id_text = ''
       or duplicate.item_count > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_BATCH_DUPLICATE_OR_MISSING_ID';
  end if;

  -- ----------------------------------------------------------
  -- Validate every requested final row before staging.
  -- ----------------------------------------------------------

  for v_item in
    select value
    from jsonb_array_elements(p_changes)
  loop
    begin
      v_semester_id :=
        (v_item ->> 'semesterId')::uuid;

      v_starts_on :=
        (v_item ->> 'startsOn')::date;

      v_ends_on :=
        (v_item ->> 'endsOn')::date;
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_INVALID_SEMESTER_BATCH_ITEM';
    end;

    v_code :=
      nullif(
        btrim(
          coalesce(
            v_item ->> 'code',
            ''
          )
        ),
        ''
      );

    if v_code is null then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_SEMESTER_CODE_REQUIRED';
    end if;

    if v_starts_on > v_ends_on then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_SEMESTER_RANGE';
    end if;

    if (v_ends_on - v_starts_on + 1) < 28
       or mod(
         v_ends_on - v_starts_on + 1,
         7
       ) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_SEMESTER_WEEK_STRUCTURE';
    end if;

    select *
    into v_existing
    from public.semesters s
    where s.id = v_semester_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_SEMESTER_NOT_FOUND';
    end if;

    if (
      v_existing.starts_on is distinct from
        v_starts_on
      or v_existing.ends_on is distinct from
        v_ends_on
    )
    and private.calendar_semester_is_materialized(
      v_existing.id,
      null
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MATERIALIZED_SEMESTER_DATES_IMMUTABLE';
    end if;

    if v_existing.code is distinct from v_code
       or v_existing.starts_on is distinct from
          v_starts_on
       or v_existing.ends_on is distinct from
          v_ends_on then
      v_changed_ids :=
        array_append(
          v_changed_ids,
          v_semester_id
        );

      v_changed_count :=
        v_changed_count + 1;
    end if;
  end loop;

  if v_changed_count = 0 then
    return jsonb_build_object(
      'changed',
        false,
      'changedCount',
        0
    );
  end if;

  -- ----------------------------------------------------------
  -- Stage changed rows outside the live calendar.
  --
  -- This avoids immediate exclusion/unique conflicts when two
  -- adjacent semesters exchange a boundary or codes are swapped.
  -- ----------------------------------------------------------

  select
    coalesce(
      max(s.ends_on),
      (
        pg_catalog.now()
        at time zone 'Asia/Seoul'
      )::date
    )
    + 3650
  into v_stage_base
  from public.semesters s;

  for v_item in
    select value
    from jsonb_array_elements(p_changes)
  loop
    v_semester_id :=
      (v_item ->> 'semesterId')::uuid;

    if not (
      v_semester_id = any(v_changed_ids)
    ) then
      continue;
    end if;

    update public.semesters
    set
      code =
        '__FORESTRING_STAGE__'
        || v_semester_id::text,

      starts_on =
        v_stage_base
        + (v_stage_index * 35),

      ends_on =
        v_stage_base
        + (v_stage_index * 35)
        + 27
    where id = v_semester_id;

    v_stage_index :=
      v_stage_index + 1;
  end loop;

  -- ----------------------------------------------------------
  -- Apply final values.
  -- ----------------------------------------------------------

  for v_item in
    select value
    from jsonb_array_elements(p_changes)
  loop
    v_semester_id :=
      (v_item ->> 'semesterId')::uuid;

    if not (
      v_semester_id = any(v_changed_ids)
    ) then
      continue;
    end if;

    v_code :=
      btrim(v_item ->> 'code');

    v_starts_on :=
      (v_item ->> 'startsOn')::date;

    v_ends_on :=
      (v_item ->> 'endsOn')::date;

    begin
      update public.semesters
      set
        code = v_code,
        starts_on = v_starts_on,
        ends_on = v_ends_on
      where id = v_semester_id;

    exception
      when unique_violation then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_SEMESTER_CODE_ALREADY_EXISTS';

      when exclusion_violation then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_SEMESTER_OVERLAP';
    end;
  end loop;

  -- ----------------------------------------------------------
  -- Final global/branch invariants.
  -- ----------------------------------------------------------

  if not private.global_semester_calendar_is_contiguous() then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_CALENDAR_NOT_CONTIGUOUS';
  end if;

  for v_branch in
    select b.id
    from public.branches b
  loop
    if not private.branch_semester_calendar_is_contiguous(
      v_branch.id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_BRANCH_SEMESTER_CALENDAR_NOT_CONTIGUOUS',
        detail = 'branch_id=' || v_branch.id::text;
    end if;
  end loop;

  if exists (
    select 1
    from public.branch_semester_overrides o
    join public.semesters s
      on s.id = o.semester_id
    where o.starts_on = s.starts_on
      and o.ends_on = s.ends_on
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REDUNDANT_SEMESTER_OVERRIDE';
  end if;

  if exists (
    select 1
    from public.closure_periods cp
    cross join lateral
      private.get_effective_semester_bounds(
        cp.branch_id,
        cp.semester_id
      ) e
    where cp.semester_id is not null
      and (
        cp.starts_on < e.starts_on
        or cp.ends_on > e.ends_on
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';
  end if;

  insert into public.audit_events (
    event_type,
    actor_id,
    details
  )
  values (
    'SEMESTER_CALENDAR_BATCH_UPDATED',
    v_actor_id,
    jsonb_build_object(
      'changedCount',
        v_changed_count,
      'changes',
        p_changes
    )
  );

  return jsonb_build_object(
    'changed',
      true,
    'changedCount',
      v_changed_count
  );
end;
$function$;


create or replace function public.apply_branch_semester_overrides_batch(
  p_branch_id uuid,
  p_changes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_item jsonb;

  v_semester_id uuid;
  v_starts_on date;
  v_ends_on date;
  v_delete boolean;

  v_existing public.branch_semester_overrides%rowtype;

  v_changed_count integer := 0;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    p_branch_id,
    false
  ) a;

  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;

  if p_changes is null
     or jsonb_typeof(p_changes) <> 'array'
     or jsonb_array_length(p_changes) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_SEMESTER_BATCH_REQUIRED';
  end if;

  if exists (
    select 1
    from (
      select
        value ->> 'semesterId' as semester_id_text,
        count(*) as item_count
      from jsonb_array_elements(p_changes)
      group by value ->> 'semesterId'
    ) duplicate
    where duplicate.semester_id_text is null
       or duplicate.semester_id_text = ''
       or duplicate.item_count > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_SEMESTER_BATCH_DUPLICATE_OR_MISSING_ID';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_changes)
  loop
    begin
      v_semester_id :=
        (v_item ->> 'semesterId')::uuid;

      v_delete :=
        coalesce(
          (v_item ->> 'delete')::boolean,
          false
        );
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_INVALID_BRANCH_SEMESTER_BATCH_ITEM';
    end;

    perform 1
    from public.semesters s
    where s.id = v_semester_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_SEMESTER_NOT_FOUND';
    end if;

    select *
    into v_existing
    from public.branch_semester_overrides o
    where o.branch_id = p_branch_id
      and o.semester_id = v_semester_id
    for update;

    if v_delete then
      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_SEMESTER_OVERRIDE_NOT_FOUND';
      end if;

      if private.calendar_semester_is_materialized(
        v_semester_id,
        p_branch_id
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE';
      end if;

      delete from public.branch_semester_overrides
      where branch_id = p_branch_id
        and semester_id = v_semester_id;

      v_changed_count :=
        v_changed_count + 1;

      continue;
    end if;

    begin
      v_starts_on :=
        (v_item ->> 'startsOn')::date;

      v_ends_on :=
        (v_item ->> 'endsOn')::date;
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_INVALID_BRANCH_SEMESTER_BATCH_ITEM';
    end;

    if v_starts_on > v_ends_on then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_SEMESTER_OVERRIDE_RANGE';
    end if;

    if (v_ends_on - v_starts_on + 1) < 28
       or mod(
         v_ends_on - v_starts_on + 1,
         7
       ) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_SEMESTER_OVERRIDE_WEEK_STRUCTURE';
    end if;

    if found
       and v_existing.starts_on =
           v_starts_on
       and v_existing.ends_on =
           v_ends_on then
      continue;
    end if;

    if private.calendar_semester_is_materialized(
      v_semester_id,
      p_branch_id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE';
    end if;

    insert into public.branch_semester_overrides (
      branch_id,
      semester_id,
      starts_on,
      ends_on,
      updated_by
    )
    values (
      p_branch_id,
      v_semester_id,
      v_starts_on,
      v_ends_on,
      v_actor_id
    )
    on conflict (
      branch_id,
      semester_id
    )
    do update
    set
      starts_on = excluded.starts_on,
      ends_on = excluded.ends_on,
      updated_by = excluded.updated_by;

    v_changed_count :=
      v_changed_count + 1;
  end loop;

  if not private.branch_semester_calendar_is_contiguous(
    p_branch_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_SEMESTER_CALENDAR_NOT_CONTIGUOUS';
  end if;

  if exists (
    select 1
    from public.closure_periods cp
    cross join lateral
      private.get_effective_semester_bounds(
        cp.branch_id,
        cp.semester_id
      ) e
    where cp.branch_id = p_branch_id
      and cp.semester_id is not null
      and (
        cp.starts_on < e.starts_on
        or cp.ends_on > e.ends_on
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';
  end if;

  if v_changed_count = 0 then
    return jsonb_build_object(
      'branchId',
        p_branch_id,
      'changed',
        false,
      'changedCount',
        0
    );
  end if;

  insert into public.audit_events (
    branch_id,
    event_type,
    actor_id,
    details
  )
  values (
    p_branch_id,
    'BRANCH_SEMESTER_CALENDAR_BATCH_UPDATED',
    v_actor_id,
    jsonb_build_object(
      'changedCount',
        v_changed_count,
      'changes',
        p_changes
    )
  );

  return jsonb_build_object(
    'branchId',
      p_branch_id,
    'changed',
      true,
    'changedCount',
      v_changed_count
  );
end;
$function$;


revoke all
on function public.apply_semester_calendar_batch(jsonb)
from public, anon;

revoke all
on function public.apply_branch_semester_overrides_batch(uuid, jsonb)
from public, anon;


grant execute
on function public.apply_semester_calendar_batch(jsonb)
to authenticated, service_role;

grant execute
on function public.apply_branch_semester_overrides_batch(uuid, jsonb)
to authenticated, service_role;
