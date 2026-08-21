begin;

do $$
declare
  v_manager_id uuid;
  v_other_manager_id uuid;
  v_branch_id uuid;

  v_teacher_id uuid;

  v_student_a_id uuid;
  v_student_b_id uuid;

  v_regular_semester_id uuid;
  v_flex_semester_id uuid;
  v_carry_semester_id uuid;

  v_regular_slot_id uuid;
  v_regular_series_id uuid;

  v_regular_right_1 uuid;
  v_regular_right_2 uuid;
  v_regular_right_3 uuid;

  v_regular_lesson_1 uuid;
  v_regular_lesson_2 uuid;
  v_regular_lesson_3 uuid;

  v_flex_plan_id uuid;

  v_flex_right_1 uuid;
  v_flex_right_2 uuid;
  v_flex_right_3 uuid;

  v_flex_lesson_1 uuid;
  v_flex_lesson_2 uuid;
  v_flex_lesson_3 uuid;

  v_carry_source_right uuid;
  v_carry_right uuid;
  v_carry_lesson uuid;

  v_teacher_cancel_right uuid;
  v_teacher_cancel_lesson uuid;

  v_result jsonb;

  v_count integer;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. FIXTURE
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    teacher_profile.id,
    student_profile.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id,
    v_student_a_id

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
      'TEST_FIXTURE_REQUIRED: manager + teacher + student';
  end if;


  -- ==========================================================
  -- 2. SECOND STUDENT
  --
  -- Keep two-student ownership tests.
  -- Temporarily normalize another student into this branch.
  -- ROLLBACK restores everything.
  -- ==========================================================

  select p.id
  into v_student_b_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id <> v_student_a_id

  order by
    case
      when p.branch_id = v_branch_id then 0
      else 1
    end,
    p.created_at

  limit 1;


  if v_student_b_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second student entity';
  end if;


  update public.profiles
  set
    branch_id = v_branch_id,
    is_active = true
  where id = v_student_b_id;


  update public.students
  set
    status =
      'active'::public.student_status,
    withdrawal_date = null
  where id = v_student_b_id;


  -- ==========================================================
  -- 3. OTHER-BRANCH MANAGER
  -- ==========================================================

  select p.id
  into v_other_manager_id

  from public.profiles p

  where p.role =
        'manager'::public.user_role

    and p.is_active = true

    and p.branch_id is not null

    and p.branch_id <>
        v_branch_id

  order by p.created_at
  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 4. TEST SEMESTERS
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-CANCEL-REGULAR-2099',
    date '2099-12-07',
    date '2100-01-03'
  )
  returning id
  into v_regular_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-CANCEL-FLEX-2100',
    date '2100-01-04',
    date '2100-01-31'
  )
  returning id
  into v_flex_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-CANCEL-CARRY-2100',
    date '2100-02-01',
    date '2100-02-28'
  )
  returning id
  into v_carry_semester_id;


  -- ==========================================================
  -- 5. REGULAR LOGICAL SLOT + SERIES
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_a_id,
    v_branch_id,
    date '2099-12-07',
    v_manager_id
  )
  returning id
  into v_regular_slot_id;


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
    v_student_a_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2099-12-07',
    v_regular_slot_id
  )
  returning id
  into v_regular_series_id;


  -- ==========================================================
  -- 6. THREE REGULAR RIGHTS
  --
  -- Same slot/semester.
  -- Student quota = 2.
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
  values
    (
      v_student_a_id,
      v_branch_id,
      v_regular_semester_id,
      v_regular_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      1,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_a_id,
      v_branch_id,
      v_regular_semester_id,
      v_regular_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      2,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_a_id,
      v_branch_id,
      v_regular_semester_id,
      v_regular_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      3,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    );


  select id into v_regular_right_1
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_regular_semester_id
    and sequence_no = 1;


  select id into v_regular_right_2
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_regular_semester_id
    and sequence_no = 2;


  select id into v_regular_right_3
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_regular_semester_id
    and sequence_no = 3;


  -- ==========================================================
  -- 7. THREE REGULAR LESSONS
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
  values
    (
      v_regular_series_id,
      v_student_a_id,
      v_teacher_id,
      timestamptz '2099-12-14 18:00:00+09',
      timestamptz '2099-12-14 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_1
    ),
    (
      v_regular_series_id,
      v_student_a_id,
      v_teacher_id,
      timestamptz '2099-12-21 18:00:00+09',
      timestamptz '2099-12-21 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_2
    ),
    (
      v_regular_series_id,
      v_student_a_id,
      v_teacher_id,
      timestamptz '2099-12-28 18:00:00+09',
      timestamptz '2099-12-28 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_3
    );


  select id into v_regular_lesson_1
  from public.lessons
  where lesson_right_id = v_regular_right_1;

  select id into v_regular_lesson_2
  from public.lessons
  where lesson_right_id = v_regular_right_2;

  select id into v_regular_lesson_3
  from public.lessons
  where lesson_right_id = v_regular_right_3;


  -- ==========================================================
  -- 8. FLEX PLAN
  --
  -- 8 base rights => floor(8 / 4) = 2 cancellations.
  -- ==========================================================

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status,
    created_by,
    updated_by
  )
  values (
    v_student_a_id,
    v_flex_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    8,
    30,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_flex_plan_id;


  -- ==========================================================
  -- 9. THREE FLEX RIGHTS
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values
    (
      v_student_a_id,
      v_branch_id,
      v_flex_semester_id,
      v_flex_semester_id,
      'flex_base'::public.lesson_right_origin,
      1,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_a_id,
      v_branch_id,
      v_flex_semester_id,
      v_flex_semester_id,
      'flex_base'::public.lesson_right_origin,
      2,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_a_id,
      v_branch_id,
      v_flex_semester_id,
      v_flex_semester_id,
      'flex_base'::public.lesson_right_origin,
      3,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    );


  select id into v_flex_right_1
  from public.lesson_rights
  where student_id = v_student_a_id
    and source_semester_id = v_flex_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 1;


  select id into v_flex_right_2
  from public.lesson_rights
  where student_id = v_student_a_id
    and source_semester_id = v_flex_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 2;


  select id into v_flex_right_3
  from public.lesson_rights
  where student_id = v_student_a_id
    and source_semester_id = v_flex_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 3;


  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values
    (
      v_student_a_id,
      v_teacher_id,
      timestamptz '2100-01-10 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_flex_right_1
    ),
    (
      v_student_a_id,
      v_teacher_id,
      timestamptz '2100-01-17 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_flex_right_2
    ),
    (
      v_student_a_id,
      v_teacher_id,
      timestamptz '2100-01-24 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_flex_right_3
    );


  select id into v_flex_lesson_1
  from public.lessons where lesson_right_id = v_flex_right_1;

  select id into v_flex_lesson_2
  from public.lessons where lesson_right_id = v_flex_right_2;

  select id into v_flex_lesson_3
  from public.lessons where lesson_right_id = v_flex_right_3;


  -- ==========================================================
  -- 10. CARRYOVER SOURCE + RIGHT
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by
  )
  values (
    v_student_a_id,
    v_branch_id,
    v_flex_semester_id,
    v_flex_semester_id,
    'flex_base'::public.lesson_right_origin,
    8,
    30,
    'expired'::public.lesson_right_status,
    v_manager_id
  )
  returning id
  into v_carry_source_right;


  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    source_right_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    carryover_count,
    created_by,
    reserved_at
  )
  values (
    v_student_a_id,
    v_branch_id,
    v_flex_semester_id,
    v_carry_semester_id,
    v_carry_source_right,
    'carryover'::public.lesson_right_origin,
    8,
    30,
    'reserved'::public.lesson_right_status,
    1,
    v_manager_id,
    now()
  )
  returning id
  into v_carry_right;


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
    v_student_a_id,
    v_teacher_id,
    timestamptz '2100-02-10 11:00:00+09',
    30,
    'flex'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_carry_right
  )
  returning id
  into v_carry_lesson;


  -- ==========================================================
  -- 11. STUDENT A LOGIN
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_a_id::text,
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
      'sub', v_student_a_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 12. REGULAR FIRST CANCEL = COUNTS
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_regular_lesson_1,
      'regular test #1'
    );


  if (v_result ->> 'countsTowardLimit')::boolean <> true
     or
     (v_result ->> 'cancellationLimit')::integer <> 2
     or
     (v_result ->> 'countedCancellationCount')::integer <> 1
     or
     (v_result ->> 'remainingCancellations')::integer <> 1 then

    raise exception
      'TEST_FAILED: regular first cancellation quota result incorrect';

  end if;


  -- ==========================================================
  -- 13. SAME REGULAR RIGHT RE-CANCEL DOES NOT COUNT AGAIN
  --
  -- Simulate a successful rebooking state.
  -- ==========================================================

  update public.lessons
  set
    status =
      'scheduled'::public.lesson_status,
    starts_at =
      timestamptz '2099-12-15 18:00:00+09',
    canceled_by = null,
    canceled_at = null,
    cancellation_reason = null
  where id = v_regular_lesson_1;


  update public.lesson_rights
  set
    status =
      'reserved'::public.lesson_right_status,
    reserved_at = now()
  where id = v_regular_right_1;


  v_result :=
    public.cancel_lesson(
      v_regular_lesson_1,
      'regular re-cancel'
    );


  if (v_result ->> 'countsTowardLimit')::boolean <> false then
    raise exception
      'TEST_FAILED: same regular right counted twice';
  end if;


  -- Exactly one counting event for this right.
  select count(*)::integer
  into v_count
  from public.lesson_cancellation_events e
  where e.lesson_right_id = v_regular_right_1
    and e.counts_toward_limit = true;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: regular right should have exactly one counting event';
  end if;


  -- ==========================================================
  -- 14. SECOND DIFFERENT REGULAR RIGHT = SECOND COUNT
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_regular_lesson_2,
      'regular test #2'
    );


  if (v_result ->> 'countsTowardLimit')::boolean <> true
     or
     (v_result ->> 'remainingCancellations')::integer <> 0 then

    raise exception
      'TEST_FAILED: regular second cancellation quota incorrect';

  end if;


  -- ==========================================================
  -- 15. THIRD DIFFERENT REGULAR RIGHT MUST FAIL
  -- ==========================================================

  v_denied := false;


  begin

    perform public.cancel_lesson(
      v_regular_lesson_3,
      'must fail'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_CANCELLATION_LIMIT_REACHED' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: regular third counting cancellation succeeded';
  end if;


  if not exists (
    select 1
    from public.lessons l
    where l.id = v_regular_lesson_3
      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: rejected regular cancellation mutated lesson';
  end if;


  -- ==========================================================
  -- 16. FLEX FIRST + SECOND COUNT
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_flex_lesson_1,
      'flex test #1'
    );


  if (v_result ->> 'cancellationLimit')::integer <> 2
     or
     (v_result ->> 'countsTowardLimit')::boolean <> true
     or
     (v_result ->> 'remainingCancellations')::integer <> 1 then

    raise exception
      'TEST_FAILED: flex first cancellation quota incorrect';

  end if;


  v_result :=
    public.cancel_lesson(
      v_flex_lesson_2,
      'flex test #2'
    );


  if (v_result ->> 'countsTowardLimit')::boolean <> true
     or
     (v_result ->> 'remainingCancellations')::integer <> 0 then

    raise exception
      'TEST_FAILED: flex second cancellation quota incorrect';

  end if;


  -- ==========================================================
  -- 17. FLEX THIRD MUST FAIL
  -- ==========================================================

  v_denied := false;


  begin

    perform public.cancel_lesson(
      v_flex_lesson_3,
      'must fail'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_CANCELLATION_LIMIT_REACHED' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: flex third counting cancellation succeeded';
  end if;


  -- ==========================================================
  -- 18. CARRYOVER STUDENT CANCEL = NO QUOTA
  -- ==========================================================

  v_result :=
    public.cancel_lesson(
      v_carry_lesson,
      'carryover cancellation'
    );


  if (v_result ->> 'countsTowardLimit')::boolean <> false then
    raise exception
      'TEST_FAILED: carryover cancellation consumed quota';
  end if;


  if (v_result -> 'cancellationLimit') <> 'null'::jsonb then
    raise exception
      'TEST_FAILED: carryover cancellation should have no quota limit';
  end if;


  -- ==========================================================
  -- 19. OTHER STUDENT MAY NOT CANCEL STUDENT A LESSON
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_b_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_student_b_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.cancel_lesson(
      v_regular_lesson_3,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: another student canceled student A lesson';
  end if;


  -- ==========================================================
  -- 20. MANAGER ACADEMY CANCEL = NO QUOTA
  --
  -- Use regular lesson #3 which student quota could not cancel.
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_result :=
    public.cancel_lesson(
      v_regular_lesson_3,
      'academy cancellation'
    );


  if v_result ->> 'origin' <> 'academy'
     or
     (v_result ->> 'countsTowardLimit')::boolean <> false then

    raise exception
      'TEST_FAILED: manager academy cancellation counted quota';
  end if;


  -- ==========================================================
  -- 21. ACTUAL DURATION ≠ ENTITLEMENT DURATION
  --
  -- Create a 30-minute entitlement with a 60-minute actual
  -- lesson, then teacher cancels it.
  --
  -- Right must remain 30.
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_b_id,
    v_branch_id,
    v_flex_semester_id,
    v_flex_semester_id,
    'flex_base'::public.lesson_right_origin,
    50,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    now()
  )
  returning id
  into v_teacher_cancel_right;


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
    v_student_b_id,
    v_teacher_id,
    timestamptz '2100-01-25 14:00:00+09',
    60,
    'flex'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_teacher_cancel_right
  )
  returning id
  into v_teacher_cancel_lesson;


  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_teacher_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_result :=
    public.cancel_lesson(
      v_teacher_cancel_lesson,
      'teacher academy cancellation'
    );


  if v_result ->> 'origin' <> 'academy'
     or
     (v_result ->> 'countsTowardLimit')::boolean <> false then

    raise exception
      'TEST_FAILED: teacher cancellation should be academy/no quota';
  end if;


  if not exists (
    select 1
    from public.lesson_rights r
    where r.id =
          v_teacher_cancel_right
      and r.status =
          'available'::public.lesson_right_status
      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: cancellation changed entitlement duration';
  end if;


  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_teacher_cancel_lesson
      and l.status =
          'canceled'::public.lesson_status
      and l.duration_minutes = 60
  ) then

    raise exception
      'TEST_FAILED: cancellation incorrectly rewrote actual duration';
  end if;


  -- ==========================================================
  -- 22. CROSS-BRANCH MANAGER DENIED
  --
  -- Re-create reserved state temporarily.
  -- ==========================================================

  update public.lessons
  set
    status =
      'scheduled'::public.lesson_status,
    canceled_by = null,
    canceled_at = null,
    cancellation_reason = null
  where id =
        v_teacher_cancel_lesson;


  update public.lesson_rights
  set
    status =
      'reserved'::public.lesson_right_status,
    reserved_at = now()
  where id =
        v_teacher_cancel_right;


  perform set_config(
    'request.jwt.claim.sub',
    v_other_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_other_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.cancel_lesson(
      v_teacher_cancel_lesson,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: cross-branch manager canceled lesson';
  end if;


  -- ==========================================================
  -- 23. CANCELLATION EVENT INTEGRITY
  -- ==========================================================

  if exists (
    select 1
    from public.lesson_cancellation_events e
    where e.counts_toward_limit = true
      and e.origin <>
          'student'::public.lesson_cancellation_origin
  ) then

    raise exception
      'TEST_FAILED: academy cancellation counted toward quota';
  end if;


  -- Student regular bucket must contain exactly TWO counting
  -- events despite lesson #1 being canceled twice.
  select count(*)::integer
  into v_count

  from public.lesson_cancellation_events e

  join public.lesson_rights r
    on r.id = e.lesson_right_id

  where e.student_id =
        v_student_a_id

    and e.counts_toward_limit = true

    and r.origin =
        'regular_base'::public.lesson_right_origin

    and r.source_semester_id =
        v_regular_semester_id

    and r.schedule_slot_id =
        v_regular_slot_id;


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: expected exactly 2 counting regular cancellations, got %',
      v_count;
  end if;


  -- Flex semester must also contain exactly TWO.
  select count(*)::integer
  into v_count

  from public.lesson_cancellation_events e

  join public.lesson_rights r
    on r.id = e.lesson_right_id

  where e.student_id =
        v_student_a_id

    and e.counts_toward_limit = true

    and r.origin =
        'flex_base'::public.lesson_right_origin

    and r.source_semester_id =
        v_flex_semester_id;


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: expected exactly 2 counting flex cancellations, got %',
      v_count;
  end if;

end;
$$;


select
  'PASS: lesson-right cancellation / regular quota / flex quota / same-right recancel / carryover / academy no-count / teacher / manager branch / duration preservation / ownership'
  as test_result;

rollback;
