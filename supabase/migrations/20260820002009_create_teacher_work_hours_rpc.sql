-- ============================================================
-- Forestring v3
-- Teacher current work-hours management
--
-- Work hours are CURRENT defaults only.
-- No historical/effective-date versions are stored.
--
-- Changes are audited separately in audit_events.
-- ============================================================


create or replace function public.replace_teacher_work_hours(
  p_teacher_id uuid,
  p_segments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_role public.user_role;

  v_before jsonb;
  v_after jsonb;

  v_segment_count integer;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


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


  -- ==========================================================
  -- TARGET TEACHER
  --
  -- Lock teacher entity so simultaneous whole-schedule
  -- replacements for the same teacher serialize.
  -- ==========================================================

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


  -- ==========================================================
  -- MANAGER BRANCH PERMISSION
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_teacher_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- INPUT
  --
  -- [
  --   {
  --     "weekday": 1,
  --     "startTime": "10:00",
  --     "endTime": "13:00"
  --   }
  -- ]
  --
  -- [] means "no work hours".
  -- ==========================================================

  if p_segments is null
     or jsonb_typeof(p_segments) <> 'array' then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WORK_HOURS_ARRAY_REQUIRED';

  end if;


  -- Validate every object before touching existing rows.
  if exists (
    select 1
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
    where
      x.weekday is null
      or x.weekday not between 1 and 7

      or x."startTime" is null
      or x."endTime" is null

      or x."startTime" !~
        '^([01][0-9]|2[0-3]):[0-5][0-9]$'

      or x."endTime" !~
        '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_WORK_HOURS_FORMAT';

  end if;


  -- Forestring scheduling uses a 15-minute grid.
  if exists (
    select 1
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
    where
      (
        extract(
          minute from x."startTime"::time
        )::integer % 15
      ) <> 0

      or (
        extract(
          minute from x."endTime"::time
        )::integer % 15
      ) <> 0
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WORK_HOURS_NOT_ON_15_MINUTE_GRID';

  end if;


  if exists (
    select 1
    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
    where
      x."startTime"::time
      >=
      x."endTime"::time
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_WORK_HOURS_RANGE';

  end if;


  -- ==========================================================
  -- INPUT OVERLAP
  --
  -- Detect before DELETE so invalid submissions never even
  -- temporarily replace the current schedule.
  -- ==========================================================

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
            (
              extract(hour from a.start_time)::integer * 60
              + extract(minute from a.start_time)::integer
            ),
            (
              extract(hour from a.end_time)::integer * 60
              + extract(minute from a.end_time)::integer
            ),
            '[)'
          )
          &&
          int4range(
            (
              extract(hour from b.start_time)::integer * 60
              + extract(minute from b.start_time)::integer
            ),
            (
              extract(hour from b.end_time)::integer * 60
              + extract(minute from b.end_time)::integer
            ),
            '[)'
          )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WORK_HOURS_OVERLAP';

  end if;


  -- ==========================================================
  -- NORMALIZED BEFORE / AFTER
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', wh.weekday,
        'startTime',
          to_char(wh.start_time, 'HH24:MI'),
        'endTime',
          to_char(wh.end_time, 'HH24:MI')
      )
      order by
        wh.weekday,
        wh.start_time,
        wh.end_time
    ),
    '[]'::jsonb
  )
  into v_before
  from public.teacher_work_hours wh
  where wh.teacher_id = p_teacher_id;


  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', q.weekday,
        'startTime', q.start_time,
        'endTime', q.end_time
      )
      order by
        q.weekday,
        q.start_time::time,
        q.end_time::time
    ),
    '[]'::jsonb
  )
  into v_after
  from (
    select
      x.weekday,
      to_char(
        x."startTime"::time,
        'HH24:MI'
      ) as start_time,
      to_char(
        x."endTime"::time,
        'HH24:MI'
      ) as end_time

    from jsonb_to_recordset(p_segments)
      as x(
        weekday integer,
        "startTime" text,
        "endTime" text
      )
  ) q;


  -- Identical save = no DB churn / no audit noise.
  if v_before = v_after then

    return jsonb_build_object(
      'teacherId', p_teacher_id,
      'branchId', v_teacher_branch_id,
      'changed', false,
      'segmentCount',
        jsonb_array_length(v_after)
    );

  end if;


  -- ==========================================================
  -- REPLACE CURRENT DEFAULTS
  -- ==========================================================

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
    x.weekday::smallint,
    x."startTime"::time,
    x."endTime"::time
  from jsonb_to_recordset(p_segments)
    as x(
      weekday integer,
      "startTime" text,
      "endTime" text
    );


  get diagnostics
    v_segment_count = row_count;


  -- ==========================================================
  -- AUDIT
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    actor_id,
    details
  )
  values (
    p_teacher_id,
    v_teacher_branch_id,
    'TEACHER_WORK_HOURS_CHANGED',
    v_actor_id,
    jsonb_build_object(
      'before', v_before,
      'after', v_after
    )
  );


  return jsonb_build_object(
    'teacherId', p_teacher_id,
    'branchId', v_teacher_branch_id,
    'changed', true,
    'segmentCount', v_segment_count
  );

end;
$$;


revoke all
on function public.replace_teacher_work_hours(
  uuid,
  jsonb
)
from public, anon;


grant execute
on function public.replace_teacher_work_hours(
  uuid,
  jsonb
)
to authenticated;


comment on function public.replace_teacher_work_hours(
  uuid,
  jsonb
) is
  'Atomically replaces a teacher current weekly work-hour defaults. Master may edit any branch; manager may edit only own branch. Empty array clears all work hours.';