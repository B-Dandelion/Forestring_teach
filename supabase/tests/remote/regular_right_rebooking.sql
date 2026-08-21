begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;

  v_teacher_a_id uuid;
  v_teacher_b_id uuid;

  v_student_id uuid;

  v_semester_id uuid;

  v_slot_id uuid;
  v_series_id uuid;

  v_right_id uuid;
  v_lesson_id uuid;

  v_original_occurrence timestamptz :=
    timestamptz '2100-03-08 18:00:00+09';

  v_rebook_date date :=
    date '2100-03-15';

  v_rebook_starts_at timestamptz :=
    timestamptz '2100-03-15 19:00:00+09';

  v_rebook_weekday smallint;

  v_result jsonb;

  v_returned_lesson_id uuid;

  v_count integer;

  v_first_event_id uuid;
  v_second_event_id uuid;
begin

  -- ==========================================================
  -- 1. FIXTURE
  --
  -- teacher A = normal teacher
  -- teacher B = manager, who is also a teachers row
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    teacher_profile.id,
    student_profile.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_a_id,
    v_student_id

  from public.profiles manager_profile

  join public.teachers manager_teacher
    on manager_teacher.id =
       manager_profile.id

  join public.profiles teacher_profile
    on teacher_profile.branch_id =
       manager_profile.branch_id

   and teacher_profile.role =
       'teacher'::public.user_role

   and teacher_profile.is_active = true

  join public.teachers teacher_entity
    on teacher_entity.id =
       teacher_profile.id

  join public.profiles student_profile
    on student_profile.branch_id =
       manager_profile.branch_id

   and student_profile.role =
       'student'::public.user_role

   and student_profile.is_active = true

  join public.students student_entity
    on student_entity.id =
       student_profile.id

   and student_entity.status =
       'active'::public.student_status

  where manager_profile.role =
        'manager'::public.user_role

    and manager_profile.is_active = true

    and manager_profile.branch_id is not null

  order by
    manager_profile.created_at,
    teacher_profile.created_at,
    student_profile.created_at

  limit 1;


  if v_manager_id is null then

    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + active student';

  end if;


  v_teacher_b_id :=
    v_manager_id;


  -- ==========================================================
  -- 2. SELECTED REBOOK WEEKDAY
  -- ==========================================================

  v_rebook_weekday :=
    extract(
      isodow
      from v_rebook_date
    )::smallint;


  -- ==========================================================
  -- 3. ISOLATE WORK HOURS / BLOCKS
  --
  -- We only need teacher B for the actual rebooking candidate.
  -- Original teacher A is still given controlled hours so the
  -- fixture remains internally coherent.
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id in (
    v_teacher_a_id,
    v_teacher_b_id
  );


  delete from public.blocked_periods
  where teacher_id in (
    v_teacher_a_id,
    v_teacher_b_id
  );


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values
    (
      v_teacher_a_id,
      v_rebook_weekday,
      time '18:00',
      time '21:00'
    ),

    (
      v_teacher_b_id,
      v_rebook_weekday,
      time '18:00',
      time '21:00'
    );


  -- ==========================================================
  -- 4. TEST SEMESTER
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-REGULAR-REBOOK-2100',
    date '2100-03-01',
    date '2100-03-28'
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 5. ISOLATE STUDENT ASSIGNMENT HISTORY
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id =
        v_student_id

    and starts_on >=
        date '2100-03-01';


  update public.teacher_student_assignments
  set ends_on =
      date '2100-02-28'

  where student_id =
        v_student_id

    and starts_on <
        date '2100-03-01'

    and (
      ends_on is null
      or ends_on >=
         date '2100-03-01'
    );


  -- ==========================================================
  -- 6. ORIGINAL ASSIGNMENT
  --
  -- Teacher A owns the student when the regular lesson was
  -- originally generated.
  --
  -- Teacher change occurs effective 03/15.
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_a_id,
    v_student_id,
    date '2100-03-01',
    date '2100-03-14'
  );


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_b_id,
    v_student_id,
    date '2100-03-15',
    null
  );


  -- ==========================================================
  -- 7. REGULAR LOGICAL SLOT
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2100-03-01',
    v_manager_id
  )
  returning id
  into v_slot_id;


  -- ==========================================================
  -- 8. HISTORICAL SERIES
  --
  -- Series permanently records teacher A as the generation
  -- rule that created the original occurrence.
  -- ==========================================================

  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_a_id,
    extract(
      isodow
      from (
        v_original_occurrence
        at time zone 'Asia/Seoul'
      )::date
    )::smallint,
    time '18:00',
    30,
    date '2100-03-01',
    v_slot_id
  )
  returning id
  into v_series_id;


  -- ==========================================================
  -- 9. REGULAR RIGHT
  --
  -- Entitlement/default duration = 30.
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_id,
    'regular_base'::public.lesson_right_origin,
    1,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    now()
  )
  returning id
  into v_right_id;


  -- ==========================================================
  -- 10. ORIGINAL REGULAR LESSON
  -- ==========================================================

  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values (
    v_series_id,
    v_student_id,
    v_teacher_a_id,
    v_original_occurrence,
    v_original_occurrence,
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_id
  )
  returning id
  into v_lesson_id;


  -- ==========================================================
  -- 11. SIMULATE PRIVILEGED ONE-OFF DURATION EDIT
  --
  -- Actual lesson = 60
  -- Entitlement remains = 30
  --
  -- This proves cancellation/rebooking restores the right's
  -- canonical duration rather than carrying forward a manual
  -- one-off override.
  -- ==========================================================

  update public.lessons
  set
    duration_minutes = 60
  where id =
        v_lesson_id;


  if not exists (
    select 1

    from public.lessons l

    join public.lesson_rights r
      on r.id = l.lesson_right_id

    where l.id =
          v_lesson_id

      and l.duration_minutes = 60

      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: failed to establish 60 actual / 30 entitlement fixture';

  end if;


  -- ==========================================================
  -- 12. LOGIN AS STUDENT
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );


  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );


  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
        v_student_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 13. FIRST CANCELLATION
  --
  -- Must consume 1 of the regular slot's 2 cancellation quota.
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_lesson_id,
      'regular rebooking e2e first cancel'
    );


  v_first_event_id :=
    (
      v_result
      ->> 'cancellationEventId'
    )::uuid;


  if (
    v_result
    ->> 'countsTowardLimit'
  )::boolean <> true then

    raise exception
      'TEST_FAILED: first regular cancellation did not count';

  end if;


  if (
    v_result
    ->> 'cancellationLimit'
  )::integer <> 2 then

    raise exception
      'TEST_FAILED: regular cancellation limit is not 2';

  end if;


  if (
    v_result
    ->> 'countedCancellationCount'
  )::integer <> 1 then

    raise exception
      'TEST_FAILED: first regular cancellation count is not 1';

  end if;


  if (
    v_result
    ->> 'remainingCancellations'
  )::integer <> 1 then

    raise exception
      'TEST_FAILED: expected 1 remaining regular cancellation';

  end if;


  -- ==========================================================
  -- 14. CANCELED LESSON + AVAILABLE SAME RIGHT
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l

    where l.id =
          v_lesson_id

      and l.status =
          'canceled'::public.lesson_status

      and l.series_id =
          v_series_id

      and l.occurrence_at =
          v_original_occurrence

      -- One-off actual duration is historical current state
      -- until it is rebooked.
      and l.duration_minutes = 60
  ) then

    raise exception
      'TEST_FAILED: first cancellation changed regular identity/state incorrectly';

  end if;


  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_right_id

      and r.status =
          'available'::public.lesson_right_status

      and r.duration_minutes = 30

      and r.schedule_slot_id =
          v_slot_id
  ) then

    raise exception
      'TEST_FAILED: first cancellation did not restore same regular right';

  end if;


  -- ==========================================================
  -- 15. AVAILABILITY MUST NOW RESOLVE TEACHER B
  --
  -- Assignment effective on selected date is authoritative.
  -- ==========================================================

  if not exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_rebook_date
    ) option_row

    where option_row.starts_at =
          v_rebook_starts_at

      and option_row.teacher_id =
          v_teacher_b_id
  ) then

    raise exception
      'TEST_FAILED: rebooking option did not resolve teacher B';

  end if;


  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_rebook_date
    ) option_row

    where option_row.teacher_id <>
          v_teacher_b_id
  ) then

    raise exception
      'TEST_FAILED: rebooking availability returned stale teacher A';

  end if;


  -- ==========================================================
  -- 16. REGULAR REBOOK
  -- ==========================================================

  v_result :=
    public.book_lesson_right(
      v_right_id,
      v_rebook_starts_at
    );


  v_returned_lesson_id :=
    (
      v_result
      ->> 'lessonId'
    )::uuid;


  -- ==========================================================
  -- 17. SAME LESSON ID MUST BE REUSED
  -- ==========================================================

  if v_returned_lesson_id <>
     v_lesson_id then

    raise exception
      'TEST_FAILED: regular rebooking changed lesson id';

  end if;


  if (
    v_result
    ->> 'reusedLesson'
  )::boolean <> true then

    raise exception
      'TEST_FAILED: regular rebooking did not report reused lesson';

  end if;


  if (
    v_result
    ->> 'regularRebooking'
  )::boolean <> true then

    raise exception
      'TEST_FAILED: regular rebooking flag was false';

  end if;


  -- ==========================================================
  -- 18. STABLE REGULAR IDENTITY + NEW ACTUAL STATE
  --
  -- PRESERVED:
  --   id
  --   right
  --   series
  --   occurrence
  --
  -- CHANGED:
  --   actual teacher A -> B
  --   actual starts_at
  --   actual duration 60 -> right default 30
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l

    where l.id =
          v_lesson_id

      and l.lesson_right_id =
          v_right_id

      and l.series_id =
          v_series_id

      and l.occurrence_at =
          v_original_occurrence

      and l.student_id =
          v_student_id

      and l.teacher_id =
          v_teacher_b_id

      and l.starts_at =
          v_rebook_starts_at

      and l.duration_minutes = 30

      and l.ends_at =
          v_rebook_starts_at
          + interval '30 minutes'

      and l.lesson_type =
          'regular'::public.lesson_type

      and l.status =
          'scheduled'::public.lesson_status

      and l.rescheduled_by =
          v_student_id

      and l.canceled_by is null

      and l.canceled_at is null

      and l.cancellation_reason is null
  ) then

    raise exception
      'TEST_FAILED: regular rebooked canonical lesson state incorrect';

  end if;


  -- ==========================================================
  -- 19. HISTORICAL SERIES MUST STILL SAY TEACHER A
  --
  -- Rebooking must never rewrite generation provenance.
  -- ==========================================================

  if not exists (
    select 1
    from public.lesson_series s

    where s.id =
          v_series_id

      and s.teacher_id =
          v_teacher_a_id

      and s.schedule_slot_id =
          v_slot_id
  ) then

    raise exception
      'TEST_FAILED: regular rebooking rewrote historical series';

  end if;


  -- ==========================================================
  -- 20. RIGHT RESERVED AGAIN
  -- ==========================================================

  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_right_id

      and r.status =
          'reserved'::public.lesson_right_status

      and r.reserved_at is not null

      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: regular right not reserved after rebooking';

  end if;


  -- ==========================================================
  -- 21. STILL EXACTLY ONE LESSON FOR THIS RIGHT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lessons l

  where l.lesson_right_id =
        v_right_id;


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: regular rebooking created duplicate lesson rows: %',
      v_count;

  end if;


  -- ==========================================================
  -- 22. SECOND CANCELLATION OF SAME RIGHT
  --
  -- Must NOT consume quota again.
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_lesson_id,
      'regular rebooking e2e second cancel'
    );


  v_second_event_id :=
    (
      v_result
      ->> 'cancellationEventId'
    )::uuid;


  if (
    v_result
    ->> 'countsTowardLimit'
  )::boolean <> false then

    raise exception
      'TEST_FAILED: same regular right consumed quota twice';

  end if;


  -- ==========================================================
  -- 23. TWO EVENTS, ONLY ONE COUNTING EVENT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_cancellation_events e

  where e.lesson_right_id =
        v_right_id;


  if v_count <> 2 then

    raise exception
      'TEST_FAILED: expected 2 cancellation events, got %',
      v_count;

  end if;


  select count(*)::integer
  into v_count

  from public.lesson_cancellation_events e

  where e.lesson_right_id =
        v_right_id

    and e.counts_toward_limit = true;


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: expected exactly 1 counting cancellation event, got %',
      v_count;

  end if;


  if v_first_event_id is null
     or
     v_second_event_id is null
     or
     v_first_event_id =
     v_second_event_id then

    raise exception
      'TEST_FAILED: cancellation event identities invalid';

  end if;


  -- ==========================================================
  -- 24. FINAL STATE
  --
  -- Same canonical lesson canceled again.
  -- Same entitlement available again.
  -- Stable occurrence still unchanged.
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l

    where l.id =
          v_lesson_id

      and l.series_id =
          v_series_id

      and l.occurrence_at =
          v_original_occurrence

      and l.teacher_id =
          v_teacher_b_id

      and l.starts_at =
          v_rebook_starts_at

      and l.duration_minutes = 30

      and l.status =
          'canceled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: final regular lesson identity/state incorrect';

  end if;


  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_right_id

      and r.status =
          'available'::public.lesson_right_status

      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: same right not restored after second cancellation';

  end if;


  -- ==========================================================
  -- 25. AUDIT
  --
  -- We expect:
  --   2 cancellation audits
  --   1 booking audit
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.semester_id =
        v_semester_id

    and a.details ->> 'rightId' =
        v_right_id::text

    and a.event_type =
        'LESSON_CANCELED';


  if v_count <> 2 then

    raise exception
      'TEST_FAILED: expected 2 cancellation audits, got %',
      v_count;

  end if;


  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.semester_id =
        v_semester_id

    and a.details ->> 'rightId' =
        v_right_id::text

    and a.event_type =
        'LESSON_RIGHT_BOOKED'

    and (
      a.details
      ->> 'regularRebooking'
    )::boolean = true

    and a.details ->> 'lessonId' =
        v_lesson_id::text

    and a.details ->> 'teacherId' =
        v_teacher_b_id::text;


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: regular rebooking audit missing or duplicated';

  end if;

end;
$$;


select
  'PASS: regular right rebooking / cancel / teacher reassignment / same lesson id / stable series+occurrence / entitlement duration restore / recancel no extra quota / audit'
  as test_result;

rollback;
