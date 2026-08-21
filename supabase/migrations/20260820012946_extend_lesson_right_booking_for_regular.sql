-- ============================================================
-- Forestring v3
-- Extend lesson-right booking to regular rebooking
--
-- Supported:
--   regular_base  -> canceled canonical regular lesson ONLY
--   flex_base     -> initial booking or canceled flex rebooking
--   carryover     -> initial booking or canceled flex rebooking
--
-- Regular rebooking preserves:
--   lesson.id
--   lesson_right_id
--   series_id
--   occurrence_at
--
-- Actual mutable scheduling fields:
--   teacher_id
--   starts_at
--   duration_minutes
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

  v_series_schedule_slot_id uuid;

  v_reused_lesson boolean := false;

  v_is_regular_rebooking boolean := false;
begin

  -- ==========================================================
  -- 1. AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
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
  -- Prevent two requests from using the same entitlement.
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


  if v_right.origin not in (
    'regular_base'::public.lesson_right_origin,
    'flex_base'::public.lesson_right_origin,
    'carryover'::public.lesson_right_origin
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_UNSUPPORTED_LESSON_RIGHT_ORIGIN';
  end if;


  -- ==========================================================
  -- 3. INPUT
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
  -- 4. RE-CHECK AUTHORITATIVE AVAILABILITY
  --
  -- Flutter may have displayed this slot earlier.
  -- The server checks it again at booking time.
  --
  -- Teacher and duration are never trusted from Flutter.
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
  -- 5. FIND EXISTING CANONICAL LESSON
  --
  -- lessons.lesson_right_id has a unique index, so there may
  -- be at most one lesson for this entitlement.
  -- ==========================================================

  select *
  into v_existing_lesson

  from public.lessons l

  where l.lesson_right_id =
        v_right.id

  for update;


  -- ==========================================================
  -- 6. REGULAR REBOOKING
  --
  -- A regular right was materialized together with its
  -- canonical regular lesson.
  --
  -- Therefore:
  --   existing lesson is REQUIRED
  --   existing lesson must be CANCELED
  --
  -- We never create a second regular lesson here.
  -- ==========================================================

  if v_right.origin =
     'regular_base'::public.lesson_right_origin then

    if not found then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_LESSON_REQUIRED';

    end if;


    if v_existing_lesson.status <>
       'canceled'::public.lesson_status then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_RIGHT_LINK_STATE_INVALID';

    end if;


    if v_existing_lesson.lesson_type <>
       'regular'::public.lesson_type then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RIGHT_LESSON_TYPE_MISMATCH';

    end if;


    if v_existing_lesson.series_id is null
       or
       v_existing_lesson.occurrence_at is null then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_LESSON_IDENTITY_INVALID';

    end if;


    -- Extra defensive integrity:
    -- the historical series must belong to the same logical
    -- regular schedule slot as the entitlement.
    select ls.schedule_slot_id
    into v_series_schedule_slot_id

    from public.lesson_series ls

    where ls.id =
          v_existing_lesson.series_id;


    if not found then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_SERIES_NOT_FOUND';

    end if;


    if v_series_schedule_slot_id is distinct from
       v_right.schedule_slot_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_SERIES_SLOT_MISMATCH';

    end if;


    v_reused_lesson :=
      true;

    v_is_regular_rebooking :=
      true;


    begin

      update public.lessons
      set
        -- Actual teacher comes from the assignment effective
        -- on the SELECTED booking date.
        teacher_id =
          v_teacher_id,

        -- Actual appointment moves.
        starts_at =
          p_new_starts_at,

        -- Cancellation restores entitlement duration.
        --
        -- Example:
        -- right = 30
        -- privileged one-off edit made actual lesson = 60
        -- cancel
        -- rebook
        -- actual lesson returns to 30.
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


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_BOOKING_SLOT_TAKEN';

    end;


  -- ==========================================================
  -- 7. FLEX / CARRYOVER
  -- ==========================================================

  else

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


      v_reused_lesson :=
        true;


      begin

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


      exception
        when exclusion_violation then

          raise exception using
            errcode = 'P0001',
            message =
              'FORESTRING_BOOKING_SLOT_TAKEN';

      end;


    else

      -- Initial flex/carryover booking.
      begin

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


      exception
        when exclusion_violation then

          raise exception using
            errcode = 'P0001',
            message =
              'FORESTRING_BOOKING_SLOT_TAKEN';

      end;

    end if;

  end if;


  -- ==========================================================
  -- 8. RESERVE SAME RIGHT
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

      'lessonType',
        v_lesson.lesson_type,

      'teacherId',
        v_teacher_id,

      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_right.duration_minutes,

      'reusedLesson',
        v_reused_lesson,

      'regularRebooking',
        v_is_regular_rebooking,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at
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

    'lessonType',
      v_lesson.lesson_type,

    'reusedLesson',
      v_reused_lesson,

    'regularRebooking',
      v_is_regular_rebooking,

    'seriesId',
      v_lesson.series_id,

    'occurrenceAt',
      v_lesson.occurrence_at,

    'rightStatus',
      'reserved'
  );

end;
$$;


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
  'Books or rebooks an available lesson entitlement. regular_base must reuse its canceled canonical regular lesson while preserving lesson ID, series and occurrence identity. flex_base/carryover may create an initial flex lesson or reuse a canceled one. Teacher, branch and duration remain server-authoritative.';