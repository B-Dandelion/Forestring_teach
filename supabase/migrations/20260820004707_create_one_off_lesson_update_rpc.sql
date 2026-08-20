-- ============================================================
-- Forestring v3
-- One-off actual lesson update
--
-- Changes ONLY:
--   lessons.starts_at
--   lessons.duration_minutes
--
-- Preserves:
--   lesson id
--   lesson_right_id
--   series_id
--   occurrence_at
--   student
--   teacher
--   branch
--
-- Therefore:
--   recurring/default schedule is NOT changed
--   entitlement duration is NOT changed
-- ============================================================


-- ============================================================
-- 1. HARD DURATION RULE FOR ACTUAL LESSONS
--
-- Existing legacy/test rows are not validated immediately.
-- New/updated rows must use a positive 15-minute multiple.
-- ============================================================

alter table public.lessons
add constraint lessons_duration_15_minute_check
check (
  duration_minutes > 0
  and duration_minutes <= 720
  and mod(duration_minutes, 15) = 0
)
not valid;


-- ============================================================
-- 2. ONE-OFF LESSON UPDATE
--
-- master:
--   any scheduled lesson
--
-- manager:
--   own-branch scheduled lesson
--
-- teacher:
--   lesson taught by themselves
--
-- student:
--   forbidden
--
--
-- Hard failures:
--   invalid duration
--   canceled lesson
--   teacher actual overlap
--   student actual overlap
--
-- Soft warnings:
--   outside teacher work hours
--   overlaps teacher blocked period
--   non-standard duration
--
-- First call:
--   p_confirm_warnings = false
--
-- If warnings exist:
--   returns requiresConfirmation = true
--   DOES NOT update.
--
-- Second call after staff confirmation:
--   p_confirm_warnings = true
-- ============================================================

create or replace function public.update_lesson_once(
  p_lesson_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_confirm_warnings boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_lesson public.lessons%rowtype;

  v_new_ends_at timestamptz;

  v_local_start timestamp;
  v_local_end timestamp;

  v_inside_work_hours boolean;
  v_overlaps_blocked boolean;

  v_warning_codes text[] :=
    array[]::text[];

  v_before jsonb;
  v_after jsonb;

  v_reason text;
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


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;


  -- ==========================================================
  -- LOCK LESSON
  -- ==========================================================

  select *
  into v_lesson
  from public.lessons l
  where l.id = p_lesson_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_NOT_FOUND';
  end if;


  if v_lesson.branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- PERMISSION
  -- ==========================================================

  if v_actor_role =
     'master'::public.user_role then

    null;


  elsif v_actor_role =
        'manager'::public.user_role then

    if not private.manager_has_branch(
      v_lesson.branch_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;


  elsif v_actor_role =
        'teacher'::public.user_role then

    if v_lesson.teacher_id <> v_actor_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_TEACHER_LESSON_FORBIDDEN';

    end if;


  else

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_UPDATE_FORBIDDEN';

  end if;


  -- ==========================================================
  -- CURRENT LESSON STATE
  -- ==========================================================

  if v_lesson.status <>
     'scheduled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ONLY_SCHEDULED_LESSON_EDITABLE';

  end if;


  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_starts_at is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_START_REQUIRED';
  end if;


  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_LESSON_DURATION';

  end if;


  v_new_ends_at :=
    p_starts_at
    +
    pg_catalog.make_interval(
      mins => p_duration_minutes
    );


  v_reason :=
    nullif(
      btrim(
        coalesce(p_reason, '')
      ),
      ''
    );


  -- ==========================================================
  -- NO-OP
  --
  -- Do this before warning checks.
  --
  -- Saving an unchanged lesson must not suddenly produce
  -- warnings simply because the current lesson happens to be
  -- outside today's work-hour defaults.
  -- ==========================================================

  if v_lesson.starts_at = p_starts_at
     and
     v_lesson.duration_minutes =
       p_duration_minutes then

    return jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'changed',
        false,

      'requiresConfirmation',
        false,

      'warningCodes',
        '[]'::jsonb,

      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes
    );

  end if;


  -- ==========================================================
  -- HARD ACTUAL COLLISION:
  -- TEACHER
  -- ==========================================================

  if exists (
    select 1
    from public.lessons other
    where other.id <> v_lesson.id

      and other.teacher_id =
          v_lesson.teacher_id

      and other.status =
          'scheduled'::public.lesson_status

      and tstzrange(
            other.starts_at,
            other.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_LESSON_OVERLAP';

  end if;


  -- ==========================================================
  -- HARD ACTUAL COLLISION:
  -- STUDENT
  -- ==========================================================

  if exists (
    select 1
    from public.lessons other
    where other.id <> v_lesson.id

      and other.student_id =
          v_lesson.student_id

      and other.status =
          'scheduled'::public.lesson_status

      and tstzrange(
            other.starts_at,
            other.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_LESSON_OVERLAP';

  end if;


  -- ==========================================================
  -- KST LOCAL VALUES
  -- ==========================================================

  v_local_start :=
    p_starts_at
    at time zone 'Asia/Seoul';


  v_local_end :=
    v_new_ends_at
    at time zone 'Asia/Seoul';


  -- ==========================================================
  -- SOFT WARNING:
  -- OUTSIDE WORK HOURS
  --
  -- The full lesson must fit inside ONE work-hour segment.
  --
  -- No configured work hours also means:
  -- outside normal work hours.
  -- ==========================================================

  select exists (
    select 1
    from public.teacher_work_hours wh

    where wh.teacher_id =
          v_lesson.teacher_id

      and wh.weekday =
          extract(
            isodow
            from v_local_start
          )::integer

      and v_local_start::date =
          v_local_end::date

      and wh.start_time <=
          v_local_start::time

      and wh.end_time >=
          v_local_end::time
  )
  into v_inside_work_hours;


  if not v_inside_work_hours then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_OUTSIDE_WORK_HOURS'
      );

  end if;


  -- ==========================================================
  -- SOFT WARNING:
  -- BLOCKED PERIOD
  -- ==========================================================

  select exists (
    select 1
    from public.blocked_periods bp

    where bp.teacher_id =
          v_lesson.teacher_id

      and tstzrange(
            bp.starts_at,
            bp.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  )
  into v_overlaps_blocked;


  if v_overlaps_blocked then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_OVERLAPS_BLOCKED_PERIOD'
      );

  end if;


  -- ==========================================================
  -- SOFT WARNING:
  -- NON-STANDARD DURATION
  --
  -- Recommended presets:
  --   15 / 30 / 60
  --
  -- Privileged staff may still use:
  --   45 / 75 / 90 / ...
  -- after explicit confirmation.
  -- ==========================================================

  if p_duration_minutes not in (
    15,
    30,
    60
  ) then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_NONSTANDARD_DURATION'
      );

  end if;


  -- ==========================================================
  -- WARNING RESPONSE WITHOUT MUTATION
  -- ==========================================================

  if cardinality(v_warning_codes) > 0
     and not coalesce(
       p_confirm_warnings,
       false
     ) then

    return jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'changed',
        false,

      'requiresConfirmation',
        true,

      'warningCodes',
        to_jsonb(v_warning_codes),

      'proposedStartsAt',
        p_starts_at,

      'proposedEndsAt',
        v_new_ends_at,

      'proposedDurationMinutes',
        p_duration_minutes
    );

  end if;


  -- ==========================================================
  -- AUDIT BEFORE
  -- ==========================================================

  v_before :=
    jsonb_build_object(
      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at,

      'lessonRightId',
        v_lesson.lesson_right_id
    );


  -- ==========================================================
  -- UPDATE ONLY THE ACTUAL LESSON
  --
  -- ends_at is recalculated by existing DB trigger.
  --
  -- occurrence_at stays unchanged.
  -- lesson_right_id stays unchanged.
  -- series_id stays unchanged.
  -- ==========================================================

  begin

    update public.lessons
    set
      starts_at =
        p_starts_at,

      duration_minutes =
        p_duration_minutes,

      rescheduled_by =
        case
          when starts_at <>
               p_starts_at
            then v_actor_id
          else rescheduled_by
        end

    where id =
          v_lesson.id

    returning *
    into v_lesson;


  exception
    when exclusion_violation then

      -- A concurrent transaction may have inserted/moved
      -- another lesson after our explicit pre-check.

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_TIME_CONFLICT';

  end;


  -- ==========================================================
  -- AUDIT AFTER
  -- ==========================================================

  v_after :=
    jsonb_build_object(
      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at,

      'lessonRightId',
        v_lesson.lesson_right_id
    );


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    v_lesson.student_id,

    v_lesson.branch_id,

    'LESSON_MANUALLY_UPDATED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'teacherId',
        v_lesson.teacher_id,

      'before',
        v_before,

      'after',
        v_after,

      'warningCodes',
        to_jsonb(v_warning_codes),

      'warningsOverridden',
        cardinality(v_warning_codes) > 0,

      'reason',
        v_reason
    )
  );


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'lessonId',
      v_lesson.id,

    'changed',
      true,

    'requiresConfirmation',
      false,

    'warningCodes',
      to_jsonb(v_warning_codes),

    'startsAt',
      v_lesson.starts_at,

    'endsAt',
      v_lesson.ends_at,

    'durationMinutes',
      v_lesson.duration_minutes
  );

end;
$$;


-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on function public.update_lesson_once(
  uuid,
  timestamptz,
  integer,
  boolean,
  text
)
from public, anon;


grant execute
on function public.update_lesson_once(
  uuid,
  timestamptz,
  integer,
  boolean,
  text
)
to authenticated;


comment on function public.update_lesson_once(
  uuid,
  timestamptz,
  integer,
  boolean,
  text
) is
  'Updates only one scheduled lesson actual start time and duration. Recurring series, occurrence identity and lesson entitlement remain unchanged. Teacher/student overlaps are hard errors; work hours, blocked periods and non-standard durations require explicit confirmation.';