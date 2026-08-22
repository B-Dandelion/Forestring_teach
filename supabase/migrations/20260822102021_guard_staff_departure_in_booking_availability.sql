-- ============================================================
-- Forestring v3
-- Hide lesson-right booking availability on/after
-- teacher withdrawal_date.
--
-- withdrawal_date is the FIRST non-working day.
--
-- selected_date < withdrawal_date  -> allowed
-- selected_date >= withdrawal_date -> hidden
--
-- lesson_right_slot_candidates is the canonical availability
-- source and is also re-checked by book_lesson_right().
-- ============================================================


create or replace function
private.lesson_right_slot_candidates(
  p_right_id uuid,
  p_selected_date date,
  p_actor_id uuid
)
returns table(
  starts_at timestamptz,
  ends_at timestamptz,
  teacher_id uuid
)
language sql
stable
security definer
set search_path = ''
as $function$

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

    where r.id =
          p_right_id

      and r.student_id =
          p_actor_id

      and r.status =
          'available'::public.lesson_right_status

      and s.status =
          'active'::public.student_status

      -- Student withdrawal_date itself is already outside
      -- enrollment.
      and (
        s.withdrawal_date is null
        or p_selected_date <
           s.withdrawal_date
      )
  ),


  semester_context as (

    select
      rc.*,
      bounds.starts_on
        as semester_starts_on,
      bounds.ends_on
        as semester_ends_on

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


    -- ========================================================
    -- STAFF DEPARTURE BOUNDARY
    --
    -- Scheduling departure intentionally does NOT rewrite an
    -- existing assignment immediately.
    --
    -- Therefore availability must independently enforce the
    -- teacher's first non-working day.
    -- ========================================================

    join public.teachers teacher
      on teacher.id =
         a.teacher_id

     and (
       teacher.withdrawal_date
         is null

       or p_selected_date <
          teacher.withdrawal_date
     )


    join public.profiles teacher_profile
      on teacher_profile.id =
         a.teacher_id

     and teacher_profile.is_active =
         true

     and teacher_profile.branch_id =
         sc.branch_id

     and teacher_profile.role in (
       'teacher'::public.user_role,
       'manager'::public.user_role
     )
  ),


  -- Generate the absolute academy 15-minute grid.
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

    -- Student self-service cutoff.
    g.slot_start >=
      pg_catalog.now()
      + interval '5 hours'


    -- Full lesson must fit inside one work-hour segment.
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

        and (
          g.slot_start
          at time zone 'Asia/Seoul'
        )::date =
        (
          g.slot_end
          at time zone 'Asia/Seoul'
        )::date
    )


    -- Academy closure.
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


    -- Teacher blocked period.
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


    -- Teacher actual lesson collision.
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


    -- Student actual lesson collision.
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

$function$;


-- Internal function only.
revoke all
on function
private.lesson_right_slot_candidates(
  uuid,
  date,
  uuid
)
from public, anon, authenticated;