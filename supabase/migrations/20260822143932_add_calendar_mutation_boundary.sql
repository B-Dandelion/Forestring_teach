-- Safe calendar mutation boundary for Forestring v3.
-- Authenticated clients keep SELECT-only table access.
-- All calendar writes go through these SECURITY DEFINER RPCs.

create or replace function private.calendar_semester_is_materialized(
  p_semester_id uuid,
  p_branch_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.student_semester_plans sp
      where sp.semester_id = p_semester_id
        and sp.status in (
          'active'::public.student_semester_plan_status,
          'completed'::public.student_semester_plan_status
        )
        and (
          p_branch_id is null
          or sp.branch_id = p_branch_id
        )
    )
    or
    exists (
      select 1
      from public.lesson_rights r
      where (
        r.source_semester_id = p_semester_id
        or r.usable_semester_id = p_semester_id
      )
        and (
          p_branch_id is null
          or r.branch_id = p_branch_id
        )
    )
    or
    exists (
      select 1
      from public.lesson_rebooking_credits c
      where (
        c.source_semester_id = p_semester_id
        or c.usable_semester_id = p_semester_id
      )
        and (
          p_branch_id is null
          or coalesce(
               c.branch_id,
               (
                 select p.branch_id
                 from public.profiles p
                 where p.id = c.student_id
               )
             ) = p_branch_id
        )
    );
$function$;

revoke all
on function private.calendar_semester_is_materialized(uuid, uuid)
from public, anon, authenticated, service_role;


create or replace function private.require_calendar_actor(
  p_branch_id uuid default null,
  p_master_only boolean default false
)
returns table(
  actor_id uuid,
  actor_role public.user_role
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(
    v_actor_id
  );

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if p_master_only then
    if v_actor_role <>
       'master'::public.user_role then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MASTER_REQUIRED';
    end if;
  else
    if v_actor_role not in (
      'master'::public.user_role,
      'manager'::public.user_role
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_STAFF_REQUIRED';
    end if;

    if v_actor_role =
       'manager'::public.user_role then
      if p_branch_id is null
         or not private.manager_has_branch(
           p_branch_id
         ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
      end if;
    end if;
  end if;

  return query
  select
    v_actor_id,
    v_actor_role;
end;
$function$;

revoke all
on function private.require_calendar_actor(uuid, boolean)
from public, anon, authenticated, service_role;


create or replace function public.upsert_semester(
  p_semester_id uuid,
  p_code text,
  p_starts_on date,
  p_ends_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_semester_id uuid;
  v_existing public.semesters%rowtype;
  v_before jsonb;
  v_changed boolean := true;

  v_branch record;
  v_code text;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    null,
    true
  ) a;

  v_code :=
    nullif(
      btrim(
        coalesce(p_code, '')
      ),
      ''
    );

  if v_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_CODE_REQUIRED';
  end if;

  if p_starts_on is null
     or p_ends_on is null
     or p_starts_on > p_ends_on then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_SEMESTER_RANGE';
  end if;

  if (p_ends_on - p_starts_on + 1) < 28
     or mod(
       p_ends_on - p_starts_on + 1,
       7
     ) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_SEMESTER_WEEK_STRUCTURE';
  end if;

  if p_semester_id is null then
    begin
      insert into public.semesters (
        code,
        starts_on,
        ends_on
      )
      values (
        v_code,
        p_starts_on,
        p_ends_on
      )
      returning id
      into v_semester_id;

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

    v_before := null;

  else
    select *
    into v_existing
    from public.semesters s
    where s.id = p_semester_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_SEMESTER_NOT_FOUND';
    end if;

    v_semester_id :=
      v_existing.id;

    v_before :=
      jsonb_build_object(
        'code',
          v_existing.code,
        'startsOn',
          v_existing.starts_on,
        'endsOn',
          v_existing.ends_on
      );

    if v_existing.code = v_code
       and v_existing.starts_on =
           p_starts_on
       and v_existing.ends_on =
           p_ends_on then
      v_changed := false;
    end if;

    if (
      v_existing.starts_on is distinct from
        p_starts_on
      or v_existing.ends_on is distinct from
        p_ends_on
    )
    and private.calendar_semester_is_materialized(
      v_existing.id,
      null
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MATERIALIZED_SEMESTER_DATES_IMMUTABLE';
    end if;

    if v_changed then
      begin
        update public.semesters
        set
          code = v_code,
          starts_on = p_starts_on,
          ends_on = p_ends_on
        where id = v_existing.id;

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
    end if;
  end if;

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
    where o.semester_id = v_semester_id
      and o.starts_on = p_starts_on
      and o.ends_on = p_ends_on
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
    where cp.semester_id = v_semester_id
      and (
        cp.starts_on < e.starts_on
        or cp.ends_on > e.ends_on
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';
  end if;

  if v_changed then
    insert into public.audit_events (
      branch_id,
      semester_id,
      event_type,
      effective_on,
      actor_id,
      details
    )
    values (
      null,
      null,
      case
        when p_semester_id is null
          then 'SEMESTER_CREATED'
        else 'SEMESTER_UPDATED'
      end,
      p_starts_on,
      v_actor_id,
      jsonb_build_object(
        'semesterId',
          v_semester_id,
        'before',
          v_before,
        'after',
          jsonb_build_object(
            'code',
              v_code,
            'startsOn',
              p_starts_on,
            'endsOn',
              p_ends_on
          )
      )
    );
  end if;

  return jsonb_build_object(
    'semesterId',
      v_semester_id,
    'changed',
      v_changed,
    'code',
      v_code,
    'startsOn',
      p_starts_on,
    'endsOn',
      p_ends_on
  );
end;
$function$;


create or replace function public.delete_semester(
  p_semester_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_semester public.semesters%rowtype;
  v_branch record;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    null,
    true
  ) a;

  select *
  into v_semester
  from public.semesters s
  where s.id = p_semester_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if exists (
    select 1
    from public.branch_semester_overrides o
    where o.semester_id = v_semester.id
  )
  or exists (
    select 1
    from public.closure_periods cp
    where cp.semester_id = v_semester.id
  )
  or exists (
    select 1
    from public.student_semester_plans sp
    where sp.semester_id = v_semester.id
  )
  or exists (
    select 1
    from public.lesson_rights r
    where r.source_semester_id = v_semester.id
       or r.usable_semester_id = v_semester.id
  )
  or exists (
    select 1
    from public.lesson_rebooking_credits c
    where c.source_semester_id = v_semester.id
       or c.usable_semester_id = v_semester.id
  )
  or exists (
    select 1
    from public.audit_events ae
    where ae.semester_id = v_semester.id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_HAS_DEPENDENCIES';
  end if;

  delete from public.semesters
  where id = v_semester.id;

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

  insert into public.audit_events (
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    'SEMESTER_DELETED',
    v_semester.starts_on,
    v_actor_id,
    jsonb_build_object(
      'semesterId',
        v_semester.id,
      'code',
        v_semester.code,
      'startsOn',
        v_semester.starts_on,
      'endsOn',
        v_semester.ends_on
    )
  );

  return jsonb_build_object(
    'semesterId',
      v_semester.id,
    'deleted',
      true
  );
end;
$function$;


create or replace function public.upsert_branch_semester_override(
  p_branch_id uuid,
  p_semester_id uuid,
  p_starts_on date,
  p_ends_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_existing public.branch_semester_overrides%rowtype;
  v_before jsonb;
  v_changed boolean := true;
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

  perform 1
  from public.semesters s
  where s.id = p_semester_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if p_starts_on is null
     or p_ends_on is null
     or p_starts_on > p_ends_on then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_SEMESTER_OVERRIDE_RANGE';
  end if;

  if (p_ends_on - p_starts_on + 1) < 28
     or mod(
       p_ends_on - p_starts_on + 1,
       7
     ) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_SEMESTER_OVERRIDE_WEEK_STRUCTURE';
  end if;

  select *
  into v_existing
  from public.branch_semester_overrides o
  where o.branch_id = p_branch_id
    and o.semester_id = p_semester_id
  for update;

  if found then
    v_before :=
      jsonb_build_object(
        'startsOn',
          v_existing.starts_on,
        'endsOn',
          v_existing.ends_on
      );

    if v_existing.starts_on = p_starts_on
       and v_existing.ends_on = p_ends_on then
      v_changed := false;
    end if;
  else
    v_before := null;
  end if;

  if v_changed
     and private.calendar_semester_is_materialized(
       p_semester_id,
       p_branch_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE';
  end if;

  if v_changed then
    insert into public.branch_semester_overrides (
      branch_id,
      semester_id,
      starts_on,
      ends_on,
      updated_by
    )
    values (
      p_branch_id,
      p_semester_id,
      p_starts_on,
      p_ends_on,
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
  end if;

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
      and cp.semester_id = p_semester_id
      and (
        cp.starts_on < e.starts_on
        or cp.ends_on > e.ends_on
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';
  end if;

  if v_changed then
    insert into public.audit_events (
      branch_id,
      semester_id,
      event_type,
      effective_on,
      actor_id,
      details
    )
    values (
      p_branch_id,
      null,
      'BRANCH_SEMESTER_OVERRIDE_UPSERTED',
      p_starts_on,
      v_actor_id,
      jsonb_build_object(
        'semesterId',
          p_semester_id,
        'before',
          v_before,
        'after',
          jsonb_build_object(
            'startsOn',
              p_starts_on,
            'endsOn',
              p_ends_on
          )
      )
    );
  end if;

  return jsonb_build_object(
    'branchId',
      p_branch_id,
    'semesterId',
      p_semester_id,
    'changed',
      v_changed,
    'startsOn',
      p_starts_on,
    'endsOn',
      p_ends_on
  );
end;
$function$;


create or replace function public.delete_branch_semester_override(
  p_branch_id uuid,
  p_semester_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_existing public.branch_semester_overrides%rowtype;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    p_branch_id,
    false
  ) a;

  select *
  into v_existing
  from public.branch_semester_overrides o
  where o.branch_id = p_branch_id
    and o.semester_id = p_semester_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_OVERRIDE_NOT_FOUND';
  end if;

  if private.calendar_semester_is_materialized(
    p_semester_id,
    p_branch_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE';
  end if;

  delete from public.branch_semester_overrides
  where branch_id = p_branch_id
    and semester_id = p_semester_id;

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
      and cp.semester_id = p_semester_id
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
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_branch_id,
    null,
    'BRANCH_SEMESTER_OVERRIDE_DELETED',
    v_existing.starts_on,
    v_actor_id,
    jsonb_build_object(
      'semesterId',
        p_semester_id,
      'startsOn',
        v_existing.starts_on,
      'endsOn',
        v_existing.ends_on
    )
  );

  return jsonb_build_object(
    'branchId',
      p_branch_id,
    'semesterId',
      p_semester_id,
    'deleted',
      true
  );
end;
$function$;


create or replace function public.upsert_closure_period(
  p_closure_id uuid,
  p_branch_id uuid,
  p_semester_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_closure_kind public.closure_kind,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_closure_id uuid;
  v_existing public.closure_periods%rowtype;

  v_before jsonb;
  v_structural_changed boolean := true;
  v_changed boolean := true;

  v_reason text;
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

  if p_starts_on is null
     or p_ends_on is null
     or p_starts_on > p_ends_on then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_CLOSURE_RANGE';
  end if;

  if p_closure_kind is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CLOSURE_KIND_REQUIRED';
  end if;

  if p_closure_kind =
     'instructional_break'::public.closure_kind then
    if p_semester_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INSTRUCTIONAL_BREAK_REQUIRES_SEMESTER';
    end if;

    if (p_ends_on - p_starts_on + 1) < 7
       or mod(
         p_ends_on - p_starts_on + 1,
         7
       ) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_INSTRUCTIONAL_BREAK_WEEK_STRUCTURE';
    end if;
  end if;

  v_reason :=
    nullif(
      btrim(
        coalesce(p_reason, '')
      ),
      ''
    );

  if p_closure_id is not null then
    select *
    into v_existing
    from public.closure_periods cp
    where cp.id = p_closure_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_CLOSURE_NOT_FOUND';
    end if;

    if v_actor_role =
       'manager'::public.user_role
       and not private.manager_has_branch(
         v_existing.branch_id
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
    end if;

    v_closure_id :=
      v_existing.id;

    v_before :=
      jsonb_build_object(
        'branchId',
          v_existing.branch_id,
        'semesterId',
          v_existing.semester_id,
        'startsOn',
          v_existing.starts_on,
        'endsOn',
          v_existing.ends_on,
        'closureKind',
          v_existing.closure_kind,
        'reason',
          v_existing.reason
      );

    v_structural_changed :=
         v_existing.branch_id is distinct from
           p_branch_id
      or v_existing.semester_id is distinct from
           p_semester_id
      or v_existing.starts_on is distinct from
           p_starts_on
      or v_existing.ends_on is distinct from
           p_ends_on
      or v_existing.closure_kind is distinct from
           p_closure_kind;

    v_changed :=
      v_structural_changed
      or v_existing.reason is distinct from
         v_reason;

  else
    v_closure_id :=
      gen_random_uuid();

    v_before := null;
  end if;

  if v_structural_changed
     and p_closure_id is not null
     and v_existing.closure_kind =
       'instructional_break'::public.closure_kind
     and v_existing.semester_id is not null
     and private.calendar_semester_is_materialized(
       v_existing.semester_id,
       v_existing.branch_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  if v_structural_changed
     and p_closure_kind =
       'instructional_break'::public.closure_kind
     and p_semester_id is not null
     and private.calendar_semester_is_materialized(
       p_semester_id,
       p_branch_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  if v_changed then
    begin
      if p_closure_id is null then
        insert into public.closure_periods (
          id,
          semester_id,
          starts_on,
          ends_on,
          reason,
          created_by,
          branch_id,
          closure_kind
        )
        values (
          v_closure_id,
          p_semester_id,
          p_starts_on,
          p_ends_on,
          v_reason,
          v_actor_id,
          p_branch_id,
          p_closure_kind
        );

      else
        update public.closure_periods
        set
          semester_id = p_semester_id,
          starts_on = p_starts_on,
          ends_on = p_ends_on,
          reason = v_reason,
          branch_id = p_branch_id,
          closure_kind = p_closure_kind
        where id = v_closure_id;
      end if;

    exception
      when exclusion_violation then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_CLOSURE_OVERLAP';
    end;
  end if;

  if v_changed then
    insert into public.audit_events (
      branch_id,
      semester_id,
      event_type,
      effective_on,
      actor_id,
      details
    )
    values (
      p_branch_id,
      null,
      case
        when p_closure_id is null
          then 'CLOSURE_CREATED'
        else 'CLOSURE_UPDATED'
      end,
      p_starts_on,
      v_actor_id,
      jsonb_build_object(
        'closureId',
          v_closure_id,
        'before',
          v_before,
        'after',
          jsonb_build_object(
            'branchId',
              p_branch_id,
            'semesterId',
              p_semester_id,
            'startsOn',
              p_starts_on,
            'endsOn',
              p_ends_on,
            'closureKind',
              p_closure_kind,
            'reason',
              v_reason
          )
      )
    );
  end if;

  return jsonb_build_object(
    'closureId',
      v_closure_id,
    'changed',
      v_changed,
    'branchId',
      p_branch_id,
    'semesterId',
      p_semester_id,
    'startsOn',
      p_starts_on,
    'endsOn',
      p_ends_on,
    'closureKind',
      p_closure_kind,
    'reason',
      v_reason
  );
end;
$function$;


create or replace function public.delete_closure_period(
  p_closure_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_existing public.closure_periods%rowtype;
begin
  select *
  into v_existing
  from public.closure_periods cp
  where cp.id = p_closure_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CLOSURE_NOT_FOUND';
  end if;

  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(
    v_existing.branch_id,
    false
  ) a;

  if v_existing.closure_kind =
     'instructional_break'::public.closure_kind
     and v_existing.semester_id is not null
     and private.calendar_semester_is_materialized(
       v_existing.semester_id,
       v_existing.branch_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  delete from public.closure_periods
  where id = v_existing.id;

  insert into public.audit_events (
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    v_existing.branch_id,
    null,
    'CLOSURE_DELETED',
    v_existing.starts_on,
    v_actor_id,
    jsonb_build_object(
      'closureId',
        v_existing.id,
      'semesterId',
        v_existing.semester_id,
      'startsOn',
        v_existing.starts_on,
      'endsOn',
        v_existing.ends_on,
      'closureKind',
        v_existing.closure_kind,
      'reason',
        v_existing.reason
    )
  );

  return jsonb_build_object(
    'closureId',
      v_existing.id,
    'deleted',
      true
  );
end;
$function$;


revoke all
on function public.upsert_semester(uuid, text, date, date)
from public, anon;

revoke all
on function public.delete_semester(uuid)
from public, anon;

revoke all
on function public.upsert_branch_semester_override(uuid, uuid, date, date)
from public, anon;

revoke all
on function public.delete_branch_semester_override(uuid, uuid)
from public, anon;

revoke all
on function public.upsert_closure_period(
  uuid,
  uuid,
  uuid,
  date,
  date,
  public.closure_kind,
  text
)
from public, anon;

revoke all
on function public.delete_closure_period(uuid)
from public, anon;


grant execute
on function public.upsert_semester(uuid, text, date, date)
to authenticated, service_role;

grant execute
on function public.delete_semester(uuid)
to authenticated, service_role;

grant execute
on function public.upsert_branch_semester_override(uuid, uuid, date, date)
to authenticated, service_role;

grant execute
on function public.delete_branch_semester_override(uuid, uuid)
to authenticated, service_role;

grant execute
on function public.upsert_closure_period(
  uuid,
  uuid,
  uuid,
  date,
  date,
  public.closure_kind,
  text
)
to authenticated, service_role;

grant execute
on function public.delete_closure_period(uuid)
to authenticated, service_role;
