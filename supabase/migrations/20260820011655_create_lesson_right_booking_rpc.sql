-- ============================================================
-- Forestring v3
-- Lesson-right booking transaction
--
-- Supports:
--   flex_base
--   carryover
--
-- Student supplies ONLY:
--   right_id
--   selected starts_at
--
-- Server resolves:
--   teacher
--   branch
--   duration
--   availability
--
-- A previously canceled FLEX lesson linked to the same right
-- is reused rather than creating another lesson row.
-- ============================================================


create or replace function public.book_lesson_right(
  p_right_id uuid,
  p_new_starts_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_actor_branch_id uuid;

  v_right public.lesson_rights%rowtype;

  v_selected_date date;

  v_teacher_id uuid;

  v_existing_lesson public.lessons%rowtype;

  v_lesson public.lessons%rowtype;

  v_reused_lesson boolean := false;
begin

  -- ==========================================================
  -- 1. AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  select p.branch_id
  into v_actor_branch_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id =
        v_actor_id

    and p.is_active = true

    and p.role =
        'student'::public.user_role

    and s.status =
        'active'::public.student_status;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;


  -- ==========================================================
  -- 2. LOCK RIGHT
  --
  -- This serializes two simultaneous booking attempts using
  -- the same entitlement.
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        p_right_id

  for update;


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


  if v_right.branch_id is distinct from
     v_actor_branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_BRANCH_MISMATCH';
  end if;


  if v_right.status <>
     'available'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE';
  end if;


  -- ==========================================================
  -- 3. RIGHT TYPE
  --
  -- Regular rights have a canonical regular lesson identity.
  -- Their cancel/rebook flow is handled separately so
  -- series_id + occurrence_at are preserved.
  -- ==========================================================

  if v_right.origin =
     'regular_base'::public.lesson_right_origin then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_RIGHT_REQUIRES_REBOOK_FLOW';

  end if;


  if v_right.origin not in (
    'flex_base'::public.lesson_right_origin,
    'carryover'::public.lesson_right_origin
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_UNSUPPORTED_LESSON_RIGHT_ORIGIN';

  end if;


  -- ==========================================================
  -- 4. INPUT
  -- ==========================================================

  if p_new_starts_at is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_START_REQUIRED';

  end if;


  v_selected_date :=
    (
      p_new_starts_at
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- 5. RE-CHECK SERVER AVAILABILITY
  --
  -- Do NOT trust a slot shown by Flutter a few seconds ago.
  --
  -- The exact start must STILL appear in the authoritative
  -- candidate engine at button-press time.
  -- ==========================================================

  select candidate.teacher_id
  into v_teacher_id

  from private.lesson_right_slot_candidates(
    v_right.id,
    v_selected_date,
    v_actor_id
  ) candidate

  where candidate.starts_at =
        p_new_starts_at

  limit 1;


  if v_teacher_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE';

  end if;


  -- ==========================================================
  -- 6. CHECK WHETHER THIS RIGHT ALREADY HAS A LESSON
  --
  -- Initial flex booking:
  --   no lesson -> INSERT
  --
  -- Flex cancellation + rebooking:
  --   canceled linked lesson -> UPDATE same row
  --
  -- This preserves one actual lesson identity per entitlement.
  -- ==========================================================

  select *
  into v_existing_lesson

  from public.lessons l

  where l.lesson_right_id =
        v_right.id

  for update;


  if found then

    if v_existing_lesson.status <>
       'canceled'::public.lesson_status then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_RIGHT_LINK_STATE_INVALID';

    end if;


    if v_existing_lesson.lesson_type <>
       'flex'::public.lesson_type then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_RIGHT_LINK_TYPE_INVALID';

    end if;


    v_reused_lesson := true;

  end if;


  -- ==========================================================
  -- 7. CREATE / REUSE ACTUAL LESSON
  -- ==========================================================

  begin

    if v_reused_lesson then

      update public.lessons
      set
        teacher_id =
          v_teacher_id,

        starts_at =
          p_new_starts_at,

        duration_minutes =
          v_right.duration_minutes,

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

      where id =
            v_existing_lesson.id

      returning *
      into v_lesson;


    else

      insert into public.lessons (
        student_id,
        teacher_id,
        starts_at,
        duration_minutes,
        lesson_type,
        status,
        lesson_right_id
      )
      values (
        v_right.student_id,
        v_teacher_id,
        p_new_starts_at,
        v_right.duration_minutes,
        'flex'::public.lesson_type,
        'scheduled'::public.lesson_status,
        v_right.id
      )

      returning *
      into v_lesson;

    end if;


  exception
    when exclusion_violation then

      -- A different booking may have taken the slot between
      -- candidate calculation and mutation.
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_BOOKING_SLOT_TAKEN';

  end;


  -- ==========================================================
  -- 8. RESERVE RIGHT
  -- ==========================================================

  update public.lesson_rights
  set
    status =
      'reserved'::public.lesson_right_status,

    reserved_at =
      pg_catalog.now()

  where id =
        v_right.id;


  -- ==========================================================
  -- 9. AUDIT
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    v_right.student_id,
    v_right.branch_id,
    v_right.usable_semester_id,
    'LESSON_RIGHT_BOOKED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'rightId',
        v_right.id,

      'lessonId',
        v_lesson.id,

      'rightOrigin',
        v_right.origin,

      'teacherId',
        v_teacher_id,

      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_right.duration_minutes,

      'reusedLesson',
        v_reused_lesson
    )
  );


  -- ==========================================================
  -- 10. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'rightId',
      v_right.id,

    'lessonId',
      v_lesson.id,

    'teacherId',
      v_teacher_id,

    'startsAt',
      v_lesson.starts_at,

    'endsAt',
      v_lesson.ends_at,

    'durationMinutes',
      v_lesson.duration_minutes,

    'reusedLesson',
      v_reused_lesson,

    'rightStatus',
      'reserved'
  );

end;
$$;


-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on function public.book_lesson_right(
  uuid,
  timestamptz
)
from public, anon;


grant execute
on function public.book_lesson_right(
  uuid,
  timestamptz
)
to authenticated;


comment on function public.book_lesson_right(
  uuid,
  timestamptz
) is
  'Books an available flex/carryover lesson right using an exact server-calculated availability candidate. Teacher, duration and branch are authoritative server state. A canceled linked flex lesson is reused on rebooking.';