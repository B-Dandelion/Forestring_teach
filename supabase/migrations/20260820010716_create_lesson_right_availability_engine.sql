-- ============================================================
-- Forestring v3
-- Lesson-right based student availability engine
--
-- Used by:
--   flex booking
--   carryover booking
--   regular cancellation rebooking
--
-- Student never supplies:
--   teacher_id
--   duration
--   branch
--
-- These are resolved by the server from authoritative state.
-- ============================================================


-- ============================================================
-- 1. INTERNAL SLOT CANDIDATES
--
-- One available lesson right
-- + one selected date
-- ->
-- student-bookable 15-minute-grid start times.
--
-- The teacher is resolved from the assignment effective on
-- the selected date.
-- ============================================================

create or replace function private.lesson_right_slot_candidates(
  p_right_id uuid,
  p_selected_date date,
  p_actor_id uuid
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz,
  teacher_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with right_context as (

    select
      r.id,
      r.student_id,
      r.branch_id,
      r.usable_semester_id,
      r.duration_minutes

    from public.lesson_rights r

    where r.id = p_right_id

      and r.student_id =
          p_actor_id

      and r.status =
          'available'::public.lesson_right_status
  ),


  semester_context as (

    select
      rc.*,
      bounds.starts_on as semester_starts_on,
      bounds.ends_on as semester_ends_on

    from right_context rc

    cross join lateral
      private.get_effective_semester_bounds(
        rc.branch_id,
        rc.usable_semester_id
      ) bounds

    where p_selected_date
      between
        bounds.starts_on
        and bounds.ends_on
  ),


  assignment_context as (

    select
      sc.*,
      a.teacher_id

    from semester_context sc

    join public.teacher_student_assignments a
      on a.student_id =
         sc.student_id

     and a.branch_id =
         sc.branch_id

     and a.starts_on <=
         p_selected_date

     and (
       a.ends_on is null
       or a.ends_on >=
          p_selected_date
     )

    join public.profiles teacher_profile
      on teacher_profile.id =
         a.teacher_id

     and teacher_profile.is_active = true

     and teacher_profile.branch_id =
         sc.branch_id

     and teacher_profile.role in (
       'teacher'::public.user_role,
       'manager'::public.user_role
     )
  ),


  -- Generate the absolute academy grid for the selected day.
  --
  -- We intentionally do NOT start generation from each
  -- work-hour start_time.
  --
  -- That keeps student booking on:
  -- 00 / 15 / 30 / 45
  --
  -- even if malformed historical work-hour data ever contains
  -- something like 10:07.
  grid as (

    select
      slot_start,

      slot_start
      +
      pg_catalog.make_interval(
        mins =>
          ac.duration_minutes
      )
        as slot_end,

      ac.student_id,
      ac.branch_id,
      ac.teacher_id,
      ac.duration_minutes

    from assignment_context ac

    cross join lateral
      pg_catalog.generate_series(
        (
          p_selected_date
          + time '00:00'
        )
        at time zone 'Asia/Seoul',

        (
          p_selected_date
          + time '23:45'
        )
        at time zone 'Asia/Seoul',

        interval '15 minutes'
      ) slot_start
  )


  select
    g.slot_start
      as starts_at,

    g.slot_end
      as ends_at,

    g.teacher_id

  from grid g

  where

    -- ========================================================
    -- 5-HOUR STUDENT SELF-SERVICE CUTOFF
    -- ========================================================

    g.slot_start >=
      pg_catalog.now()
      + interval '5 hours'


    -- ========================================================
    -- FULL LESSON MUST FIT INSIDE ONE WORK-HOUR SEGMENT
    -- ========================================================

    and exists (
      select 1

      from public.teacher_work_hours wh

      where wh.teacher_id =
            g.teacher_id

        and wh.weekday =
            extract(
              isodow
              from p_selected_date
            )::smallint

        and wh.start_time <=
            (
              g.slot_start
              at time zone 'Asia/Seoul'
            )::time

        and wh.end_time >=
            (
              g.slot_end
              at time zone 'Asia/Seoul'
            )::time

        -- Work-hour rows never represent overnight ranges.
        and (
          g.slot_start
          at time zone 'Asia/Seoul'
        )::date =
        (
          g.slot_end
          at time zone 'Asia/Seoul'
        )::date
    )


    -- ========================================================
    -- ANY ACADEMY CLOSURE IS HARD FOR STUDENT SELF-BOOKING
    --
    -- instructional_break:
    --   removed teaching week
    --
    -- ordinary:
    --   date-specific academy closure
    -- ========================================================

    and not exists (
      select 1

      from public.closure_periods cp

      where cp.branch_id =
            g.branch_id

        and p_selected_date
            between
            cp.starts_on
            and cp.ends_on
    )


    -- ========================================================
    -- TEACHER BLOCKED PERIOD
    -- ========================================================

    and not exists (
      select 1

      from public.blocked_periods bp

      where bp.teacher_id =
            g.teacher_id

        and tstzrange(
              g.slot_start,
              g.slot_end,
              '[)'
            )
            &&
            tstzrange(
              bp.starts_at,
              bp.ends_at,
              '[)'
            )
    )


    -- ========================================================
    -- TEACHER ACTUAL LESSON COLLISION
    -- ========================================================

    and not exists (
      select 1

      from public.lessons l

      where l.teacher_id =
            g.teacher_id

        and l.status =
            'scheduled'::public.lesson_status

        and tstzrange(
              g.slot_start,
              g.slot_end,
              '[)'
            )
            &&
            tstzrange(
              l.starts_at,
              l.ends_at,
              '[)'
            )
    )


    -- ========================================================
    -- STUDENT ACTUAL LESSON COLLISION
    -- ========================================================

    and not exists (
      select 1

      from public.lessons l

      where l.student_id =
            g.student_id

        and l.status =
            'scheduled'::public.lesson_status

        and tstzrange(
              g.slot_start,
              g.slot_end,
              '[)'
            )
            &&
            tstzrange(
              l.starts_at,
              l.ends_at,
              '[)'
            )
    )

  order by
    g.slot_start;
$$;


revoke all
on function private.lesson_right_slot_candidates(
  uuid,
  date,
  uuid
)
from public, anon, authenticated;


-- ============================================================
-- 2. PUBLIC STUDENT AVAILABILITY RPC
-- ============================================================

create or replace function public.get_lesson_right_booking_options(
  p_right_id uuid,
  p_selected_date date
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz,
  teacher_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_right public.lesson_rights%rowtype;

  v_semester_start date;
  v_semester_end date;

  v_assignment_teacher_id uuid;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';

  end if;


  if not exists (
    select 1

    from public.profiles p

    join public.students s
      on s.id = p.id

    where p.id =
          v_actor_id

      and p.is_active = true

      and p.role =
          'student'::public.user_role

      and s.status =
          'active'::public.student_status
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';

  end if;


  -- ==========================================================
  -- RIGHT
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        p_right_id;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';

  end if;


  if v_right.student_id <>
     v_actor_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_FORBIDDEN';

  end if;


  if v_right.status <>
     'available'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE';

  end if;


  -- ==========================================================
  -- EFFECTIVE USABLE SEMESTER
  -- ==========================================================

  select
    bounds.starts_on,
    bounds.ends_on

  into
    v_semester_start,
    v_semester_end

  from private.get_effective_semester_bounds(
    v_right.branch_id,
    v_right.usable_semester_id
  ) bounds;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_FOUND';

  end if;


  if p_selected_date
     not between
       v_semester_start
       and v_semester_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_DATE_OUTSIDE_USABLE_SEMESTER';

  end if;


  -- ==========================================================
  -- ASSIGNMENT ON SELECTED DATE
  --
  -- Rights intentionally do not permanently store teacher_id.
  -- ==========================================================

  select a.teacher_id
  into v_assignment_teacher_id

  from public.teacher_student_assignments a

  join public.profiles teacher_profile
    on teacher_profile.id =
       a.teacher_id

  where a.student_id =
        v_right.student_id

    and a.branch_id =
        v_right.branch_id

    and a.starts_on <=
        p_selected_date

    and (
      a.ends_on is null
      or a.ends_on >=
         p_selected_date
    )

    and teacher_profile.is_active = true

    and teacher_profile.branch_id =
        v_right.branch_id

    and teacher_profile.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

  limit 1;


  if v_assignment_teacher_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_ASSIGNMENT_REQUIRED';

  end if;


  -- ==========================================================
  -- RETURN SAFE SERVER-CALCULATED CANDIDATES
  -- ==========================================================

  return query

  select
    candidate.starts_at,
    candidate.ends_at,
    candidate.teacher_id

  from private.lesson_right_slot_candidates(
    p_right_id,
    p_selected_date,
    v_actor_id
  ) candidate;

end;
$$;


-- ============================================================
-- 3. PRIVILEGES
-- ============================================================

revoke all
on function public.get_lesson_right_booking_options(
  uuid,
  date
)
from public, anon;


grant execute
on function public.get_lesson_right_booking_options(
  uuid,
  date
)
to authenticated;


comment on function public.get_lesson_right_booking_options(
  uuid,
  date
) is
  'Returns student-safe booking candidates for one available lesson right. Teacher, branch and duration are derived server-side; student candidates must fit work hours and avoid closures, blocked periods and actual lesson collisions.';