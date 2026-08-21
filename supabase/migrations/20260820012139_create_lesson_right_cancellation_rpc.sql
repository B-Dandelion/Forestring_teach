-- ============================================================
-- Forestring v3
-- Lesson-right based cancellation lifecycle
--
-- Replaces the OLD credit-issuing cancel_lesson().
--
-- Cancellation restores THE SAME lesson right.
-- No new replacement credit/right is created.
-- ============================================================


-- ============================================================
-- 1. ONE COUNTING CANCELLATION PER RIGHT
--
-- original lesson
--   cancel  -> counts
--   rebook
--   cancel  -> does NOT count again
-- ============================================================

create unique index if not exists
  lesson_cancellation_events_one_count_per_right
on public.lesson_cancellation_events (
  lesson_right_id
)
where counts_toward_limit = true;


-- ============================================================
-- 2. REMOVE OLD CREDIT-BASED CANCEL RPC
-- ============================================================

drop function if exists
  public.cancel_lesson(uuid);


-- ============================================================
-- 3. RIGHTS-BASED CANCEL RPC
-- ============================================================

create function public.cancel_lesson(
  p_lesson_id uuid,
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
  v_actor_branch_id uuid;

  v_lesson public.lessons%rowtype;
  v_right public.lesson_rights%rowtype;

  v_origin public.lesson_cancellation_origin;

  v_reason text;

  v_counts_toward_limit boolean := false;

  v_cancellation_limit integer;
  v_count_before integer := 0;
  v_count_after integer := 0;
  v_remaining integer;

  v_flex_base_count integer;

  v_event_id uuid;
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


  select
    p.role,
    p.branch_id

  into
    v_actor_role,
    v_actor_branch_id

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_USER_REQUIRED';

  end if;


  v_reason :=
    nullif(
      btrim(
        coalesce(
          p_reason,
          ''
        )
      ),
      ''
    );


  -- ==========================================================
  -- LOCK LESSON
  -- ==========================================================

  select *
  into v_lesson

  from public.lessons l

  where l.id =
        p_lesson_id

  for update;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_NOT_FOUND';

  end if;


  if v_lesson.status <>
     'scheduled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_NOT_SCHEDULED';

  end if;


  -- Production rights-based cancellation applies only to
  -- canonical entitled lessons.
  if v_lesson.lesson_right_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_REQUIRED';

  end if;


  -- ==========================================================
  -- LOCK RIGHT
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        v_lesson.lesson_right_id

  for update;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';

  end if;


  if v_right.student_id <>
       v_lesson.student_id
     or
     v_right.branch_id <>
       v_lesson.branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_IDENTITY_MISMATCH';

  end if;


  if v_right.status <>
     'reserved'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_RESERVED';

  end if;


  -- ==========================================================
  -- ACTOR / ORIGIN
  -- ==========================================================

  if v_actor_role =
     'student'::public.user_role then

    if v_lesson.student_id <>
       v_actor_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_FORBIDDEN';

    end if;


    -- Student self-service cancellation cutoff.
    if v_lesson.starts_at <
       pg_catalog.now()
       + interval '5 hours' then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_CANCELLATION_TOO_LATE';

    end if;


    v_origin :=
      'student'::public.lesson_cancellation_origin;


  elsif v_actor_role =
        'master'::public.user_role then

    v_origin :=
      'academy'::public.lesson_cancellation_origin;


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


    v_origin :=
      'academy'::public.lesson_cancellation_origin;


  elsif v_actor_role =
        'teacher'::public.user_role then

    if v_lesson.teacher_id <>
       v_actor_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_TEACHER_LESSON_FORBIDDEN';

    end if;


    v_origin :=
      'academy'::public.lesson_cancellation_origin;


  else

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_FORBIDDEN';

  end if;


  -- ==========================================================
  -- STUDENT CANCELLATION QUOTA
  -- ==========================================================

  if v_origin =
     'student'::public.lesson_cancellation_origin then

    -- --------------------------------------------------------
    -- If this entitlement has ALREADY consumed one quota,
    -- a later re-cancel does not consume another.
    -- --------------------------------------------------------

    if exists (
      select 1

      from public.lesson_cancellation_events e

      where e.lesson_right_id =
            v_right.id

        and e.counts_toward_limit = true
    ) then

      v_counts_toward_limit :=
        false;


    -- --------------------------------------------------------
    -- CARRYOVER
    --
    -- Canceling/rebooking an already-carried extra entitlement
    -- does not create another entitlement and consumes no new
    -- cancellation quota.
    -- --------------------------------------------------------

    elsif v_right.origin =
          'carryover'::public.lesson_right_origin then

      v_counts_toward_limit :=
        false;


    -- --------------------------------------------------------
    -- REGULAR
    --
    -- Limit = 2 counting cancellations
    -- per logical regular slot / source semester.
    --
    -- Lock the logical slot to serialize concurrent cancels
    -- of different rights belonging to the same quota bucket.
    -- --------------------------------------------------------

    elsif v_right.origin =
          'regular_base'::public.lesson_right_origin then

      perform 1
      from public.regular_schedule_slots rs

      where rs.id =
            v_right.schedule_slot_id

      for update;


      if not found then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';

      end if;


      v_cancellation_limit :=
        2;


      select count(*)::integer
      into v_count_before

      from public.lesson_cancellation_events e

      join public.lesson_rights counted_right
        on counted_right.id =
           e.lesson_right_id

      where e.student_id =
            v_right.student_id

        and e.origin =
            'student'::public.lesson_cancellation_origin

        and e.counts_toward_limit = true

        and counted_right.origin =
            'regular_base'::public.lesson_right_origin

        and counted_right.source_semester_id =
            v_right.source_semester_id

        and counted_right.schedule_slot_id =
            v_right.schedule_slot_id;


      if v_count_before >=
         v_cancellation_limit then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_CANCELLATION_LIMIT_REACHED';

      end if;


      v_counts_toward_limit :=
        true;


    -- --------------------------------------------------------
    -- FLEX
    --
    -- Limit = floor(base right count / 4)
    -- per student / source semester.
    --
    -- Lock the semester plan to serialize quota calculations.
    -- --------------------------------------------------------

    elsif v_right.origin =
          'flex_base'::public.lesson_right_origin then

      select
        sp.flex_base_right_count

      into
        v_flex_base_count

      from public.student_semester_plans sp

      where sp.student_id =
            v_right.student_id

        and sp.semester_id =
            v_right.source_semester_id

        and sp.student_type_snapshot =
            'flex'::public.student_type

      for update;


      if not found
         or v_flex_base_count is null then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_FLEX_SEMESTER_PLAN_REQUIRED';

      end if;


      v_cancellation_limit :=
        floor(
          v_flex_base_count::numeric / 4
        )::integer;


      select count(*)::integer
      into v_count_before

      from public.lesson_cancellation_events e

      join public.lesson_rights counted_right
        on counted_right.id =
           e.lesson_right_id

      where e.student_id =
            v_right.student_id

        and e.origin =
            'student'::public.lesson_cancellation_origin

        and e.counts_toward_limit = true

        and counted_right.origin =
            'flex_base'::public.lesson_right_origin

        and counted_right.source_semester_id =
            v_right.source_semester_id;


      if v_count_before >=
         v_cancellation_limit then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_CANCELLATION_LIMIT_REACHED';

      end if;


      v_counts_toward_limit :=
        true;


    else

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_UNSUPPORTED_LESSON_RIGHT_ORIGIN';

    end if;

  end if;


  -- ==========================================================
  -- CANCEL CANONICAL LESSON
  -- ==========================================================

  update public.lessons
  set
    status =
      'canceled'::public.lesson_status,

    canceled_by =
      v_actor_id,

    canceled_at =
      pg_catalog.now(),

    cancellation_reason =
      case
        when v_reason is not null
          then v_reason

        when v_origin =
             'student'::public.lesson_cancellation_origin
          then 'student_cancellation'

        else
          'academy_cancellation'
      end

  where id =
        v_lesson.id;


  -- ==========================================================
  -- RESTORE THE SAME RIGHT
  --
  -- Important:
  -- lesson.duration_minutes may have been manually edited.
  --
  -- right.duration_minutes is NOT changed.
  -- ==========================================================

  update public.lesson_rights
  set
    status =
      'available'::public.lesson_right_status,

    reserved_at =
      null

  where id =
        v_right.id;


  -- ==========================================================
  -- IMMUTABLE CANCELLATION EVENT
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    reason
  )
  values (
    v_lesson.id,
    v_right.id,
    v_right.student_id,
    v_right.branch_id,
    v_origin,
    v_actor_id,
    v_counts_toward_limit,
    v_reason
  )
  returning id
  into v_event_id;


  -- ==========================================================
  -- QUOTA RESULT
  -- ==========================================================

  if v_origin =
       'student'::public.lesson_cancellation_origin
     and v_cancellation_limit is not null then

    if v_counts_toward_limit then
      v_count_after :=
        v_count_before + 1;
    else
      v_count_after :=
        v_count_before;
    end if;


    v_remaining :=
      greatest(
        v_cancellation_limit
        - v_count_after,
        0
      );

  else

    v_cancellation_limit :=
      null;

    v_count_after :=
      0;

    v_remaining :=
      null;

  end if;


  -- ==========================================================
  -- GENERAL AUDIT
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
    'LESSON_CANCELED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'rightId',
        v_right.id,

      'rightOrigin',
        v_right.origin,

      'cancellationOrigin',
        v_origin,

      'countsTowardLimit',
        v_counts_toward_limit,

      'cancellationLimit',
        v_cancellation_limit,

      'countedCancellationCount',
        case
          when v_cancellation_limit is null
            then null
          else v_count_after
        end,

      'remainingCancellations',
        v_remaining,

      'entitlementDurationMinutes',
        v_right.duration_minutes,

      'actualLessonDurationMinutes',
        v_lesson.duration_minutes,

      'reason',
        v_reason,

      'cancellationEventId',
        v_event_id
    )
  );


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'lessonId',
      v_lesson.id,

    'rightId',
      v_right.id,

    'cancellationEventId',
      v_event_id,

    'origin',
      v_origin,

    'rightStatus',
      'available',

    'countsTowardLimit',
      v_counts_toward_limit,

    'cancellationLimit',
      v_cancellation_limit,

    'countedCancellationCount',
      case
        when v_cancellation_limit is null
          then null
        else v_count_after
      end,

    'remainingCancellations',
      v_remaining
  );

end;
$$;


-- ============================================================
-- 4. PRIVILEGES
-- ============================================================

revoke all
on function public.cancel_lesson(
  uuid,
  text
)
from public, anon;


grant execute
on function public.cancel_lesson(
  uuid,
  text
)
to authenticated;


comment on function public.cancel_lesson(
  uuid,
  text
) is
  'Cancels a canonical right-backed scheduled lesson and restores the same entitlement. Student cancellation quotas are regular=2 per logical slot/semester and flex=floor(base rights/4) per semester; academy cancellations and carryover re-cancellations do not consume quota.';