-- ============================================================
-- Forestring v3 - Student rebooking RPCs
--
-- Student flow:
--
-- cancel_lesson()
--      ↓
-- rebooking credit issued
--      ↓
-- get_rebooking_options()
--      ↓
-- rebook_lesson()
--
-- Scheduling calculations are server-side.
-- Flutter does not inspect other students' lessons.
-- ============================================================


-- ============================================================
-- CREDIT SCHEMA CORRECTION
--
-- The same lesson may be:
--
-- original lesson
--   -> cancel
--   -> rebook
--   -> cancel again
--   -> rebook again
--
-- as long as the series/semester cancellation limit is not
-- exceeded.
--
-- Therefore source_lesson_id must NOT be globally unique.
-- ============================================================

alter table public.lesson_rebooking_credits
drop constraint if exists
  lesson_rebooking_credits_source_lesson_id_key;

create index if not exists
  lesson_rebooking_credits_source_lesson_idx
on public.lesson_rebooking_credits(source_lesson_id);


-- ============================================================
-- INTERNAL AVAILABLE-SLOT CALCULATOR
--
-- Important:
--
-- 15 minutes is the candidate START-TIME grid.
--
-- A 45-minute lesson is NOT treated as three stored tokens.
-- PostgreSQL checks the full interval:
--
--   [10:15, 11:00)
--
-- against work hours, lessons and blocked periods.
-- ============================================================

create or replace function private.rebooking_slot_candidates(
  p_credit_id uuid,
  p_selected_date date,
  p_actor_id uuid
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with credit as (
    select
      c.id,
      c.student_id,
      c.teacher_id,
      c.duration_minutes,
      c.usable_semester_id
    from public.lesson_rebooking_credits c
    where c.id = p_credit_id
      and c.student_id = p_actor_id
      and c.status =
        'available'::public.rebooking_credit_status
      and (
        c.expires_at is null
        or c.expires_at > pg_catalog.now()
      )
  ),

  usable_semester as (
    select
      s.id,
      s.starts_on,
      s.ends_on
    from public.semesters s
    join credit c
      on c.usable_semester_id = s.id
    where p_selected_date
      between s.starts_on and s.ends_on
  ),

  work_segments as (
    select
      wh.start_time,
      wh.end_time
    from public.teacher_work_hours wh
    join credit c
      on c.teacher_id = wh.teacher_id
    where wh.weekday =
      extract(isodow from p_selected_date)::smallint
  ),

  candidates as (
    select
      slot_start as starts_at,

      slot_start
        + pg_catalog.make_interval(
            mins => c.duration_minutes
          ) as ends_at,

      c.student_id,
      c.teacher_id

    from credit c

    join usable_semester us
      on true

    join work_segments wh
      on true

    cross join lateral
      pg_catalog.generate_series(
        (
          p_selected_date + wh.start_time
        ) at time zone 'Asia/Seoul',

        (
          (
            p_selected_date + wh.end_time
          ) at time zone 'Asia/Seoul'
        )
        - pg_catalog.make_interval(
            mins => c.duration_minutes
          ),

        interval '15 minutes'
      ) as slot_start
  )

  select
    candidate.starts_at,
    candidate.ends_at

  from candidates candidate

  where

    -- Booking/rebooking must be at least five hours away.
    candidate.starts_at
      >= pg_catalog.now() + interval '5 hours'


    -- Academy-wide closure.
    and not exists (
      select 1
      from public.closure_periods cp
      where p_selected_date
        between cp.starts_on and cp.ends_on
    )


    -- Teacher-specific unavailable period.
    and not exists (
      select 1
      from public.blocked_periods bp
      where bp.teacher_id =
            candidate.teacher_id

        and tstzrange(
              candidate.starts_at,
              candidate.ends_at,
              '[)'
            )
            &&
            tstzrange(
              bp.starts_at,
              bp.ends_at,
              '[)'
            )
    )


    -- Any scheduled lesson for the teacher.
    and not exists (
      select 1
      from public.lessons l
      where l.teacher_id =
            candidate.teacher_id

        and l.status =
            'scheduled'::public.lesson_status

        and tstzrange(
              candidate.starts_at,
              candidate.ends_at,
              '[)'
            )
            &&
            tstzrange(
              l.starts_at,
              l.ends_at,
              '[)'
            )
    )


    -- The student may theoretically have another teacher,
    -- so protect the student's own schedule independently too.
    and not exists (
      select 1
      from public.lessons l
      where l.student_id =
            candidate.student_id

        and l.status =
            'scheduled'::public.lesson_status

        and tstzrange(
              candidate.starts_at,
              candidate.ends_at,
              '[)'
            )
            &&
            tstzrange(
              l.starts_at,
              l.ends_at,
              '[)'
            )
    )

  order by candidate.starts_at;
$$;


revoke all
on function private.rebooking_slot_candidates(
  uuid,
  date,
  uuid
)
from public, anon, authenticated;


-- ============================================================
-- CANCEL LESSON
--
-- Student cancellation rules:
--
-- - authenticated active student only
-- - own regular lesson only
-- - scheduled lesson only
-- - current semester only
-- - at least 5 hours before lesson
-- - max 2 cancellations PER lesson series PER semester
--
-- One successful cancellation creates one credit.
-- ============================================================

create or replace function public.cancel_lesson(
  p_lesson_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_lesson public.lessons%rowtype;
  v_semester public.semesters%rowtype;

  v_lesson_date date;
  v_today date;

  v_cancel_count integer;
  v_cancellation_no smallint;

  v_credit_id uuid;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.is_active = true
      and p.role = 'student'::public.user_role
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_REQUIRED';
  end if;


  -- Lock the actual lesson.
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


  if v_lesson.student_id <> v_actor_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_FORBIDDEN';
  end if;


  if v_lesson.lesson_type <>
     'regular'::public.lesson_type
     or v_lesson.series_id is null then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MAKEUP_NOT_CANCELLABLE';
  end if;


  if v_lesson.status <>
     'scheduled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_ALREADY_CANCELED';
  end if;


  if v_lesson.starts_at
     < pg_catalog.now() + interval '5 hours' then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CANCELLATION_TOO_LATE';
  end if;


  -- Cancellation limits belong to the semester in which
  -- the lesson is ACTUALLY scheduled.
  v_lesson_date :=
    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date;


  select *
  into v_semester
  from public.semesters s
  where v_lesson_date
    between s.starts_on and s.ends_on;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;


  -- Preserve v2 rule:
  -- future-semester lessons cannot be canceled yet.
  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_today
     not between
       v_semester.starts_on
       and v_semester.ends_on then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_NOT_CURRENT_SEMESTER';
  end if;


  -- Serialize cancellation-credit creation for this series.
  perform 1
  from public.lesson_series ls
  where ls.id = v_lesson.series_id
  for update;


  select count(*)::integer
  into v_cancel_count
  from public.lesson_rebooking_credits c
  where c.source_series_id =
        v_lesson.series_id
    and c.source_semester_id =
        v_semester.id;


  if v_cancel_count >= 2 then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_LIMIT_REACHED';
  end if;


  v_cancellation_no :=
    (v_cancel_count + 1)::smallint;


  -- Cancel canonical lesson.
  update public.lessons
  set
    status =
      'canceled'::public.lesson_status,

    canceled_by =
      v_actor_id,

    canceled_at =
      pg_catalog.now(),

    cancellation_reason =
      'student_cancellation'

  where id = p_lesson_id;


  -- Issue one replacement right.
  insert into public.lesson_rebooking_credits (
    student_id,
    source_lesson_id,
    source_series_id,
    source_semester_id,
    usable_semester_id,
    teacher_id,
    duration_minutes,
    cancellation_no
  )
  values (
    v_lesson.student_id,
    v_lesson.id,
    v_lesson.series_id,
    v_semester.id,
    v_semester.id,
    v_lesson.teacher_id,
    v_lesson.duration_minutes,
    v_cancellation_no
  )
  returning id
  into v_credit_id;


  return pg_catalog.jsonb_build_object(
    'lessonId',
    v_lesson.id,

    'creditId',
    v_credit_id,

    'cancellationNo',
    v_cancellation_no,

    'remainingCancellations',
    2 - v_cancellation_no
  );
end;
$$;


-- ============================================================
-- GET REBOOKING OPTIONS
--
-- Flutter sends:
--
-- credit_id
-- selected calendar date
--
-- It does NOT send:
--
-- teacher_id
-- duration
-- other students' lessons
--
-- Those are resolved on the server.
-- ============================================================

create or replace function public.get_rebooking_options(
  p_credit_id uuid,
  p_selected_date date
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_credit public.lesson_rebooking_credits%rowtype;
  v_semester public.semesters%rowtype;
begin
  v_actor_id := auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.is_active = true
      and p.role = 'student'::public.user_role
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_REQUIRED';
  end if;


  select *
  into v_credit
  from public.lesson_rebooking_credits c
  where c.id = p_credit_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_NOT_FOUND';
  end if;


  if v_credit.student_id <> v_actor_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_FORBIDDEN';
  end if;


  if v_credit.status <>
     'available'::public.rebooking_credit_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_NOT_AVAILABLE';
  end if;


  if v_credit.expires_at is not null
     and v_credit.expires_at <= pg_catalog.now() then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_EXPIRED';
  end if;


  select *
  into v_semester
  from public.semesters s
  where s.id = v_credit.usable_semester_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CREDIT_SEMESTER_NOT_FOUND';
  end if;


  if p_selected_date
     not between
       v_semester.starts_on
       and v_semester.ends_on then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REBOOK_DATE_OUTSIDE_SEMESTER';
  end if;


  return query

  select
    candidate.starts_at,
    candidate.ends_at

  from private.rebooking_slot_candidates(
    p_credit_id,
    p_selected_date,
    v_actor_id
  ) candidate;
end;
$$;


-- ============================================================
-- REBOOK LESSON
--
-- Important concurrency model:
--
-- 1. Candidate is checked again at button press.
-- 2. Credit row is locked.
-- 3. Lesson row is locked.
-- 4. DB exclusion constraints remain the final protection
--    against simultaneous bookings.
-- ============================================================

create or replace function public.rebook_lesson(
  p_credit_id uuid,
  p_new_starts_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_credit public.lesson_rebooking_credits%rowtype;
  v_lesson public.lessons%rowtype;
  v_semester public.semesters%rowtype;

  v_candidate_date date;
  v_new_ends_at timestamptz;
begin
  v_actor_id := auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.is_active = true
      and p.role = 'student'::public.user_role
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_REQUIRED';
  end if;


  -- Lock credit first.
  select *
  into v_credit
  from public.lesson_rebooking_credits c
  where c.id = p_credit_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_NOT_FOUND';
  end if;


  if v_credit.student_id <> v_actor_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_FORBIDDEN';
  end if;


  if v_credit.status <>
     'available'::public.rebooking_credit_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_NOT_AVAILABLE';
  end if;


  if v_credit.expires_at is not null
     and v_credit.expires_at <= pg_catalog.now() then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_CREDIT_EXPIRED';
  end if;


  -- Lock canonical lesson.
  select *
  into v_lesson
  from public.lessons l
  where l.id = v_credit.source_lesson_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_LESSON_NOT_FOUND';
  end if;


  if v_lesson.student_id <> v_actor_id
     or v_lesson.series_id <>
        v_credit.source_series_id
     or v_lesson.teacher_id <>
        v_credit.teacher_id
     or v_lesson.duration_minutes <>
        v_credit.duration_minutes then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CREDIT_INTEGRITY_ERROR';
  end if;


  if v_lesson.status <>
     'canceled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_LESSON_NOT_CANCELED';
  end if;


  v_candidate_date :=
    (
      p_new_starts_at
      at time zone 'Asia/Seoul'
    )::date;


  select *
  into v_semester
  from public.semesters s
  where s.id = v_credit.usable_semester_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CREDIT_SEMESTER_NOT_FOUND';
  end if;


  if v_candidate_date
     not between
       v_semester.starts_on
       and v_semester.ends_on then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REBOOK_DATE_OUTSIDE_SEMESTER';
  end if;


  -- Re-evaluate availability at the exact moment
  -- the student presses the booking button.
  if not exists (
    select 1
    from private.rebooking_slot_candidates(
      p_credit_id,
      v_candidate_date,
      v_actor_id
    ) candidate
    where candidate.starts_at =
          p_new_starts_at
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SLOT_NOT_AVAILABLE';
  end if;


  -- Even after the check above, another transaction could
  -- attempt the same slot simultaneously.
  --
  -- lessons_teacher_no_overlap / lessons_student_no_overlap
  -- are the final authority.
  begin
    update public.lessons
    set
      starts_at =
        p_new_starts_at,

      status =
        'scheduled'::public.lesson_status,

      rescheduled_by =
        v_actor_id,

      canceled_by =
        null,

      canceled_at =
        null,

      cancellation_reason =
        null

    where id = v_lesson.id

    returning ends_at
    into v_new_ends_at;

  exception
    when exclusion_violation then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_SLOT_ALREADY_TAKEN';
  end;


  update public.lesson_rebooking_credits
  set
    status =
      'consumed'::public.rebooking_credit_status,

    consumed_at =
      pg_catalog.now(),

    consumed_starts_at =
      p_new_starts_at

  where id = p_credit_id;


  return pg_catalog.jsonb_build_object(
    'lessonId',
    v_lesson.id,

    'creditId',
    p_credit_id,

    'startsAt',
    p_new_starts_at,

    'endsAt',
    v_new_ends_at
  );
end;
$$;


-- ============================================================
-- FUNCTION PERMISSIONS
-- ============================================================

revoke all
on function public.cancel_lesson(uuid)
from public, anon;

revoke all
on function public.get_rebooking_options(uuid, date)
from public, anon;

revoke all
on function public.rebook_lesson(uuid, timestamptz)
from public, anon;


grant execute
on function public.cancel_lesson(uuid)
to authenticated;

grant execute
on function public.get_rebooking_options(uuid, date)
to authenticated;

grant execute
on function public.rebook_lesson(uuid, timestamptz)
to authenticated;
