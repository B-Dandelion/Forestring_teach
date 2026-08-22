with
today_context as (
  select
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date
      as today
),

available_rights as (
  select
    r.id,
    r.student_id,
    r.branch_id,
    r.usable_semester_id
  from public.lesson_rights r
  where r.status =
        'available'::public.lesson_right_status
),

rights_with_bounds as (
  select
    r.*,
    b.starts_on,
    b.ends_on
  from available_rights r

  cross join lateral
    private.get_effective_semester_bounds(
      r.branch_id,
      r.usable_semester_id
    ) b
),

future_rights as (
  select r.*
  from rights_with_bounds r
  cross join today_context t
  where r.ends_on >=
        t.today
),

active_assignments as (
  select distinct
    a.student_id,
    a.teacher_id,
    a.branch_id
  from public.teacher_student_assignments a
  cross join today_context t
  where a.ends_on is null
     or a.ends_on >=
        t.today
),

candidate_exists as (
  select exists (
    select 1

    from (
      select
        r.id,
        r.student_id

      from available_rights r

      limit 50
    ) r

    cross join today_context t

    cross join lateral
      pg_catalog.generate_series(
        t.today::timestamp,
        (t.today + 90)::timestamp,
        interval '1 day'
      ) d

    cross join lateral
      private.lesson_right_slot_candidates(
        r.id,
        d::date,
        r.student_id
      ) c

    limit 1
  ) as value
)

select
  (
    select count(*)
    from available_rights
  ) as available_right_count,

  (
    select count(*)
    from future_rights
  ) as future_usable_right_count,

  (
    select count(*)
    from active_assignments
  ) as current_or_future_assignment_count,

  (
    select count(*)
    from public.teacher_work_hours
  ) as teacher_work_hour_count,

  (
    select value
    from candidate_exists
  ) as has_bookable_slot_next_90_days;
