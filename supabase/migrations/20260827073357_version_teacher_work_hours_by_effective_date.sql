-- ============================================================
-- Forestring v3
-- Effective-dated teacher work hours
--
-- Keep public.teacher_work_hours as the current snapshot for
-- backwards compatibility while private version tables become
-- authoritative for date-aware scheduling checks.
-- ============================================================

create table if not exists private.teacher_work_hour_versions (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  effective_from date not null,
  effective_until date,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint teacher_work_hour_versions_range_check
    check (effective_until is null or effective_until >= effective_from),
  constraint teacher_work_hour_versions_teacher_start_key
    unique (teacher_id, effective_from),
  constraint teacher_work_hour_versions_no_overlap
    exclude using gist (
      teacher_id with =,
      daterange(
        effective_from,
        case
          when effective_until is null then 'infinity'::date
          else effective_until + 1
        end,
        '[)'
      ) with &&
    )
);

create table if not exists private.teacher_work_hour_entries (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references private.teacher_work_hour_versions(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint teacher_work_hour_entries_time_check check (start_time < end_time),
  constraint teacher_work_hour_entries_minute_precision_check check (
    extract(second from start_time) = 0
    and extract(second from end_time) = 0
  ),
  constraint teacher_work_hour_entries_no_overlap
    exclude using gist (
      version_id with =,
      weekday with =,
      int4range(
        extract(hour from start_time)::integer * 60
          + extract(minute from start_time)::integer,
        extract(hour from end_time)::integer * 60
          + extract(minute from end_time)::integer,
        '[)'
      ) with &&
    )
);

-- Seed the current static snapshot as the first dated version.
insert into private.teacher_work_hour_versions (
  teacher_id,
  effective_from
)
select distinct
  wh.teacher_id,
  (pg_catalog.now() at time zone 'Asia/Seoul')::date
from public.teacher_work_hours wh
where not exists (
  select 1
  from private.teacher_work_hour_versions v
  where v.teacher_id = wh.teacher_id
)
on conflict (teacher_id, effective_from) do nothing;

insert into private.teacher_work_hour_entries (
  version_id,
  weekday,
  start_time,
  end_time
)
select
  v.id,
  wh.weekday,
  wh.start_time,
  wh.end_time
from public.teacher_work_hours wh
join private.teacher_work_hour_versions v
  on v.teacher_id = wh.teacher_id
 and v.effective_from =
     (pg_catalog.now() at time zone 'Asia/Seoul')::date
where not exists (
  select 1
  from private.teacher_work_hour_entries e
  where e.version_id = v.id
);

create or replace function private.teacher_work_hours_for_date(
  p_teacher_id uuid,
  p_on_date date
)
returns table (
  teacher_id uuid,
  weekday smallint,
  start_time time,
  end_time time
)
language sql
stable
security definer
set search_path = ''
as $$
  with active_version as (
    select v.id
    from private.teacher_work_hour_versions v
    where v.teacher_id = p_teacher_id
      and v.effective_from <= p_on_date
      and (
        v.effective_until is null
        or v.effective_until >= p_on_date
      )
    order by v.effective_from desc
    limit 1
  )
  select
    p_teacher_id,
    e.weekday,
    e.start_time,
    e.end_time
  from active_version v
  join private.teacher_work_hour_entries e
    on e.version_id = v.id

  union all

  select
    wh.teacher_id,
    wh.weekday,
    wh.start_time,
    wh.end_time
  from public.teacher_work_hours wh
  where wh.teacher_id = p_teacher_id
    and not exists (
      select 1 from active_version
    );
$$;

create or replace function private.teacher_is_within_work_hours(
  p_teacher_id uuid,
  p_on_date date,
  p_weekday integer,
  p_start_time time,
  p_end_time time
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.teacher_work_hours_for_date(
      p_teacher_id,
      p_on_date
    ) wh
    where wh.weekday = p_weekday
      and wh.start_time <= p_start_time
      and wh.end_time >= p_end_time
  );
$$;

create or replace function public.get_teacher_work_hours_for_date(
  p_teacher_id uuid,
  p_on_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_teacher_branch_id uuid;
  v_version private.teacher_work_hour_versions%rowtype;
  v_hours jsonb;
begin
  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

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

  select p.branch_id
  into v_teacher_branch_id
  from public.profiles p
  join public.teachers t on t.id = p.id
  where p.id = p_teacher_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_teacher_branch_id) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  elsif v_actor_role = 'teacher'::public.user_role
        and v_actor_id <> p_teacher_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';
  elsif v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role,
    'teacher'::public.user_role
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';
  end if;

  if p_on_date is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WORK_HOURS_EFFECTIVE_DATE_REQUIRED';
  end if;

  select *
  into v_version
  from private.teacher_work_hour_versions v
  where v.teacher_id = p_teacher_id
    and v.effective_from <= p_on_date
    and (
      v.effective_until is null
      or v.effective_until >= p_on_date
    )
  order by v.effective_from desc
  limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', wh.weekday,
        'startTime', to_char(wh.start_time, 'HH24:MI'),
        'endTime', to_char(wh.end_time, 'HH24:MI')
      )
      order by wh.weekday, wh.start_time, wh.end_time
    ),
    '[]'::jsonb
  )
  into v_hours
  from private.teacher_work_hours_for_date(
    p_teacher_id,
    p_on_date
  ) wh;

  return jsonb_build_object(
    'teacherId', p_teacher_id,
    'onDate', p_on_date,
    'versionId',
      case when v_version.id is null then null else v_version.id end,
    'effectiveFrom',
      case when v_version.id is null then null else v_version.effective_from end,
    'effectiveUntil',
      case when v_version.id is null then null else v_version.effective_until end,
    'hours', v_hours
  );
end;
$$;

create or replace function public.replace_teacher_work_hours_effective(
  p_teacher_id uuid,
  p_effective_on date,
  p_segments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_role public.user_role;
  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_before jsonb;
  v_after jsonb;
  v_version private.teacher_work_hour_versions%rowtype;
  v_previous private.teacher_work_hour_versions%rowtype;
  v_next_start date;
  v_version_id uuid;
  v_segment_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';
  end if;

  perform 1
  from public.teachers t
  where t.id = p_teacher_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;

  select
    p.branch_id,
    p.is_active,
    p.role
  into
    v_teacher_branch_id,
    v_teacher_active,
    v_teacher_role
  from public.profiles p
  where p.id = p_teacher_id;

  if v_teacher_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_BRANCH_REQUIRED';
  end if;

  if not v_teacher_active
     or v_teacher_role not in (
       'teacher'::public.user_role,
       'manager'::public.user_role
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_TEACHER_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_teacher_branch_id) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if p_effective_on is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WORK_HOURS_EFFECTIVE_DATE_REQUIRED';
  end if;

  if p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BACKDATED_WORK_HOURS_CHANGE_FORBIDDEN';
  end if;

  if p_segments is null
     or jsonb_typeof(p_segments) <> 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WORK_HOURS_ARRAY_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
    where x.weekday is null
       or x.weekday not between 1 and 7
       or x."startTime" is null
       or x."endTime" is null
       or x."startTime" !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or x."endTime" !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_WORK_HOURS_FORMAT';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
    where extract(minute from x."startTime"::time)::integer % 15 <> 0
       or extract(minute from x."endTime"::time)::integer % 15 <> 0
       or x."startTime"::time >= x."endTime"::time
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_WORK_HOURS_RANGE';
  end if;

  if exists (
    with segments as (
      select
        row_number() over () as rn,
        x.weekday,
        x."startTime"::time as start_time,
        x."endTime"::time as end_time
      from jsonb_to_recordset(p_segments)
        as x(
          weekday integer,
          "startTime" text,
          "endTime" text
        )
    )
    select 1
    from segments a
    join segments b
      on a.rn < b.rn
     and a.weekday = b.weekday
     and int4range(
           extract(hour from a.start_time)::integer * 60
             + extract(minute from a.start_time)::integer,
           extract(hour from a.end_time)::integer * 60
             + extract(minute from a.end_time)::integer,
           '[)'
         )
         && int4range(
              extract(hour from b.start_time)::integer * 60
                + extract(minute from b.start_time)::integer,
              extract(hour from b.end_time)::integer * 60
                + extract(minute from b.end_time)::integer,
              '[)'
            )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WORK_HOURS_OVERLAP';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', wh.weekday,
        'startTime', to_char(wh.start_time, 'HH24:MI'),
        'endTime', to_char(wh.end_time, 'HH24:MI')
      )
      order by wh.weekday, wh.start_time, wh.end_time
    ),
    '[]'::jsonb
  )
  into v_before
  from private.teacher_work_hours_for_date(
    p_teacher_id,
    p_effective_on
  ) wh;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', q.weekday,
        'startTime', q.start_time,
        'endTime', q.end_time
      )
      order by q.weekday, q.start_time::time, q.end_time::time
    ),
    '[]'::jsonb
  )
  into v_after
  from (
    select
      x.weekday,
      to_char(x."startTime"::time, 'HH24:MI') as start_time,
      to_char(x."endTime"::time, 'HH24:MI') as end_time
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
  ) q;

  if v_before = v_after then
    return jsonb_build_object(
      'teacherId', p_teacher_id,
      'branchId', v_teacher_branch_id,
      'effectiveOn', p_effective_on,
      'changed', false,
      'segmentCount', jsonb_array_length(v_after)
    );
  end if;

  select *
  into v_version
  from private.teacher_work_hour_versions v
  where v.teacher_id = p_teacher_id
    and v.effective_from = p_effective_on
  for update;

  if found then
    v_version_id := v_version.id;

    delete from private.teacher_work_hour_entries e
    where e.version_id = v_version_id;
  else
    select *
    into v_previous
    from private.teacher_work_hour_versions v
    where v.teacher_id = p_teacher_id
      and v.effective_from < p_effective_on
    order by v.effective_from desc
    limit 1
    for update;

    select min(v.effective_from)
    into v_next_start
    from private.teacher_work_hour_versions v
    where v.teacher_id = p_teacher_id
      and v.effective_from > p_effective_on;

    if v_previous.id is null
       and p_effective_on > v_today then
      insert into private.teacher_work_hour_versions (
        teacher_id,
        effective_from,
        effective_until,
        created_by
      )
      values (
        p_teacher_id,
        v_today,
        p_effective_on - 1,
        v_actor_id
      )
      returning id into v_previous.id;

      insert into private.teacher_work_hour_entries (
        version_id,
        weekday,
        start_time,
        end_time
      )
      select
        v_previous.id,
        wh.weekday,
        wh.start_time,
        wh.end_time
      from public.teacher_work_hours wh
      where wh.teacher_id = p_teacher_id;
    elsif v_previous.id is not null then
      update private.teacher_work_hour_versions
      set
        effective_until = p_effective_on - 1,
        updated_at = pg_catalog.now()
      where id = v_previous.id;
    end if;

    insert into private.teacher_work_hour_versions (
      teacher_id,
      effective_from,
      effective_until,
      created_by
    )
    values (
      p_teacher_id,
      p_effective_on,
      case
        when v_next_start is null then null
        else v_next_start - 1
      end,
      v_actor_id
    )
    returning id into v_version_id;
  end if;

  insert into private.teacher_work_hour_entries (
    version_id,
    weekday,
    start_time,
    end_time
  )
  select
    v_version_id,
    x.weekday::smallint,
    x."startTime"::time,
    x."endTime"::time
  from jsonb_to_recordset(p_segments)
    as x(
      weekday integer,
      "startTime" text,
      "endTime" text
    );

  get diagnostics v_segment_count = row_count;

  update private.teacher_work_hour_versions
  set updated_at = pg_catalog.now()
  where id = v_version_id;

  if p_effective_on = v_today then
    delete from public.teacher_work_hours
    where teacher_id = p_teacher_id;

    insert into public.teacher_work_hours (
      teacher_id,
      weekday,
      start_time,
      end_time
    )
    select
      p_teacher_id,
      e.weekday,
      e.start_time,
      e.end_time
    from private.teacher_work_hour_entries e
    where e.version_id = v_version_id;
  end if;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_teacher_id,
    v_teacher_branch_id,
    'TEACHER_WORK_HOURS_CHANGED',
    p_effective_on,
    v_actor_id,
    jsonb_build_object(
      'before', v_before,
      'after', v_after,
      'effectiveOn', p_effective_on,
      'versionId', v_version_id
    )
  );

  return jsonb_build_object(
    'teacherId', p_teacher_id,
    'branchId', v_teacher_branch_id,
    'effectiveOn', p_effective_on,
    'changed', true,
    'segmentCount', v_segment_count,
    'versionId', v_version_id
  );
end;
$$;

-- Backwards-compatible wrapper for already-installed clients.
create or replace function public.replace_teacher_work_hours(
  p_teacher_id uuid,
  p_segments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.replace_teacher_work_hours_effective(
    p_teacher_id,
    (pg_catalog.now() at time zone 'Asia/Seoul')::date,
    p_segments
  );
end;
$$;

create or replace function private.refresh_current_teacher_work_hours_snapshot()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_teacher record;
  v_count integer := 0;
begin
  for v_teacher in
    select distinct v.teacher_id
    from private.teacher_work_hour_versions v
    where v.effective_from <= v_today
      and (
        v.effective_until is null
        or v.effective_until >= v_today
      )
  loop
    delete from public.teacher_work_hours wh
    where wh.teacher_id = v_teacher.teacher_id;

    insert into public.teacher_work_hours (
      teacher_id,
      weekday,
      start_time,
      end_time
    )
    select
      v_teacher.teacher_id,
      e.weekday,
      e.start_time,
      e.end_time
    from private.teacher_work_hour_versions v
    join private.teacher_work_hour_entries e
      on e.version_id = v.id
    where v.teacher_id = v_teacher.teacher_id
      and v.effective_from <= v_today
      and (
        v.effective_until is null
        or v.effective_until >= v_today
      )
    order by e.weekday, e.start_time;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Patch every scheduling path that currently reads the legacy
-- snapshot so it resolves work hours for the relevant date.
do $$
declare
  v_oid oid;
  v_def text;
  v_new text;
begin
  v_oid := to_regprocedure(
    'private.lesson_right_slot_candidates(uuid,date,uuid)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(g.teacher_id, p_selected_date) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: lesson_right_slot_candidates';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'private.rebuild_future_regular_semester(uuid,uuid)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(v_series.teacher_id, v_candidate.lesson_date) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: rebuild_future_regular_semester';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.activate_student_semester_plan(uuid)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(v_candidate.teacher_id, v_candidate.lesson_date) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: activate_student_semester_plan';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.add_regular_schedule(uuid,uuid,smallint,time without time zone,integer,date)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(p_teacher_id, p_effective_on) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: add_regular_schedule';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(p_teacher_id, p_effective_on) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: change_regular_schedule';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.create_makeup_lesson(uuid,uuid,timestamp with time zone,integer,boolean,text)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(p_teacher_id, v_local_start::date) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: create_makeup_lesson';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(p_teacher_id, v_semester_start) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: initialize_regular_student_semester';
    end if;
    execute v_new;
  end if;

  v_oid := to_regprocedure(
    'public.update_lesson_once(uuid,timestamp with time zone,integer,boolean,text)'
  );
  if v_oid is not null then
    select pg_get_functiondef(v_oid) into v_def;
    v_new := replace(
      v_def,
      'from public.teacher_work_hours wh',
      'from private.teacher_work_hours_for_date(v_lesson.teacher_id, v_local_start::date) wh'
    );
    if v_new = v_def then
      raise exception 'work-hours patch failed: update_lesson_once';
    end if;
    execute v_new;
  end if;
end;
$$;

revoke all
on function public.get_teacher_work_hours_for_date(uuid, date)
from public, anon;

grant execute
on function public.get_teacher_work_hours_for_date(uuid, date)
to authenticated;

revoke all
on function public.replace_teacher_work_hours_effective(uuid, date, jsonb)
from public, anon;

grant execute
on function public.replace_teacher_work_hours_effective(uuid, date, jsonb)
to authenticated;

revoke all
on function public.replace_teacher_work_hours(uuid, jsonb)
from public, anon;

grant execute
on function public.replace_teacher_work_hours(uuid, jsonb)
to authenticated;

-- Sync the legacy current snapshot at 00:02 KST so older installed
-- clients still display the correct current hours when a future
-- version becomes active.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'forestring-sync-teacher-work-hours'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'forestring-sync-teacher-work-hours',
    '2 15 * * *',
    'select private.refresh_current_teacher_work_hours_snapshot();'
  );
end;
$$;
