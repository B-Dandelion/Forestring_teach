-- ============================================================
-- Forestring v3
-- Guard lesson booking/scheduling after student withdrawal date
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

    join public.students s
      on s.id =
         r.student_id

    where r.id = p_right_id

      and r.student_id =
          p_actor_id

      and r.status =
          'available'::public.lesson_right_status

      and s.status =
          'active'::public.student_status

      -- Scheduled withdrawal:
      --
      -- withdrawal_date itself is already outside enrollment.
      --
      -- Example:
      -- withdrawal_date = 2026-09-15
      --
      -- 9/14 booking -> allowed
      -- 9/15 booking -> hidden
      -- 9/16 booking -> hidden
      and (
        s.withdrawal_date is null
        or p_selected_date <
           s.withdrawal_date
      )
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
-- FINAL AUTHORITATIVE WITHDRAWAL BOUNDARY
--
-- Availability filtering is UX.
-- This trigger is the actual integrity rule.
--
-- It protects EVERY scheduled-lesson write path:
--
--   book_lesson_right()
--   update_lesson_once()
--   regular schedule reconciliation
--   semester materialization
--   future administrative RPCs
--
-- Existing future lessons are NOT touched merely by scheduling
-- a withdrawal. finalize_student_withdrawal() later hard-deletes
-- them at the effective date.
-- ============================================================

create or replace function
public.assert_lesson_before_student_withdrawal()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_student_status public.student_status;
  v_withdrawal_date date;
  v_withdrawal_cutoff timestamptz;
begin

  -- Canceled lessons do not represent an active appointment.
  --
  -- This also allows an existing future lesson to be canceled
  -- while withdrawal is pending.
  if new.status <>
     'scheduled'::public.lesson_status then

    return new;

  end if;


  -- Lock the student row.
  --
  -- schedule_student_withdrawal() also locks this row, so a
  -- concurrent booking and withdrawal scheduling operation
  -- becomes serialized instead of racing.
  select
    s.status,
    s.withdrawal_date

  into
    v_student_status,
    v_withdrawal_date

  from public.students s

  where s.id =
        new.student_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_ACTIVE';

  end if;


  if v_withdrawal_date is null then
    return new;
  end if;


  -- Withdrawal takes effect at 00:00 KST.
  v_withdrawal_cutoff :=
    (
      v_withdrawal_date::timestamp
      at time zone 'Asia/Seoul'
    );


  if new.starts_at >=
     v_withdrawal_cutoff then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_ON_OR_AFTER_WITHDRAWAL';

  end if;


  return new;

end;
$$;


drop trigger if exists
  lessons_assert_student_withdrawal_boundary
on public.lessons;


create trigger
  lessons_assert_student_withdrawal_boundary

before insert
or update of
  student_id,
  starts_at,
  status

on public.lessons

for each row

execute function
  public.assert_lesson_before_student_withdrawal();


comment on function
public.assert_lesson_before_student_withdrawal()
is
  'Prevents any scheduled lesson from being created or moved to the student withdrawal date or later. The student row is locked so concurrent withdrawal scheduling and lesson booking cannot race.';
