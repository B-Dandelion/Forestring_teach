begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_source_semester_id uuid;
  v_target_semester_id uuid;

  v_source_plan_id uuid;
  v_target_plan_id uuid;

  v_slot_id uuid;
  v_series_id uuid;

  v_right_1 uuid;
  v_right_2 uuid;
  v_right_3 uuid;
  v_right_4 uuid;

  v_lesson_1 uuid;

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


  update public.students
  set
    student_type =
      'regular'::public.student_type,

    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_student_id;


  -- ==========================================================
  -- 2. SYNTHETIC CONSECUTIVE 4-WEEK SEMESTERS
  --
  -- source:
  --   2002-01-07 ~ 2002-02-03
  --
  -- target:
  --   2002-02-04 ~ 2002-03-03
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-REGULAR-TO-FLEX-SOURCE-2002',
    date '2002-01-07',
    date '2002-02-03'
  )
  returning id
  into v_source_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-REGULAR-TO-FLEX-TARGET-2002',
    date '2002-02-04',
    date '2002-03-03'
  )
  returning id
  into v_target_semester_id;


  -- ==========================================================
  -- 3. SOURCE REGULAR PLAN
  -- ==========================================================

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values (
    v_student_id,
    v_source_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_source_plan_id;


  -- ==========================================================
  -- 4. TARGET FLEX PLAN
  --
  -- 4 base rights x 30 minutes.
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
    v_student_id,
    v_target_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    4,
    30,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_target_plan_id;


  -- ==========================================================
  -- 5. HISTORICAL ASSIGNMENT
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_id,
    v_student_id,
    date '2001-12-01',
    date '2002-03-03'
  );


  -- ==========================================================
  -- 6. REGULAR LOGICAL SLOT + SERIES
  --
  -- They intentionally continue beyond source semester.
  -- Transition must close them at 2002-02-03.
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
    date '2001-12-01',
    v_manager_id
  )
  returning id
  into v_slot_id;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2001-12-01',
    v_branch_id,
    v_slot_id
  )
  returning id
  into v_series_id;


  -- ==========================================================
  -- 7. FOUR SOURCE REGULAR RIGHTS
  --
  -- #1:
  --   canceled / available -> carryover
  --
  -- #2-4:
  --   completed scheduled lessons -> consumed at finalization
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
      v_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      1,
      30,
      'available'::public.lesson_right_status,
      v_manager_id,
      null
    ),
    (
      v_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      2,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      3,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      4,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    );


  select id into v_right_1
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 1;

  select id into v_right_2
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 2;

  select id into v_right_3
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 3;

  select id into v_right_4
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 4;


  -- ==========================================================
  -- 8. SOURCE CANONICAL LESSONS
  -- ==========================================================

  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values
    (
      v_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2002-01-07 18:00:00+09',
      timestamptz '2002-01-07 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_right_1,
      v_student_id,
      timestamptz '2002-01-06 12:00:00+09',
      'semester transition test'
    ),
    (
      v_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2002-01-14 18:00:00+09',
      timestamptz '2002-01-14 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_2,
      null,
      null,
      null
    ),
    (
      v_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2002-01-21 18:00:00+09',
      timestamptz '2002-01-21 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_3,
      null,
      null,
      null
    ),
    (
      v_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2002-01-28 18:00:00+09',
      timestamptz '2002-01-28 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_4,
      null,
      null,
      null
    );


  select id
  into v_lesson_1
  from public.lessons
  where lesson_right_id =
        v_right_1;


  -- ==========================================================
  -- 9. CANCELLATION HISTORY
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    canceled_at,
    reason
  )
  values (
    v_lesson_1,
    v_right_1,
    v_student_id,
    v_branch_id,
    'student'::public.lesson_cancellation_origin,
    v_student_id,
    true,
    timestamptz '2002-01-06 12:00:00+09',
    'semester transition test'
  );


  -- ==========================================================
  -- 10. STUDENT MUST NOT BE ABLE TO TRANSITION
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
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_SEMESTER_TRANSITION_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: student transitioned own semester';
  end if;


  -- Rejected call must not mutate anything.
  if not exists (
    select 1
    from public.student_semester_plans
    where id = v_source_plan_id
      and status =
          'active'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: rejected transition mutated source plan';
  end if;


  -- ==========================================================
  -- 11. MANAGER TRANSITION
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
    public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> true
     or
     (v_result ->> 'studentTypeChanged')::boolean <> true
     or
     v_result ->> 'previousStudentType' <> 'regular'
     or
     v_result ->> 'studentType' <> 'flex' then

    raise exception
      'TEST_FAILED: transition result incorrect: %',
      v_result;
  end if;


  if (v_result ->> 'closedRegularSlotCount')::integer <> 1
     or
     (v_result ->> 'closedRegularSeriesCount')::integer <> 1 then

    raise exception
      'TEST_FAILED: regular schedules not closed: %',
      v_result;
  end if;


  -- ==========================================================
  -- 12. CURRENT STUDENT TYPE
  -- ==========================================================

  if not exists (
    select 1

    from public.students s

    where s.id =
          v_student_id

      and s.student_type =
          'flex'::public.student_type
  ) then

    raise exception
      'TEST_FAILED: students.student_type did not become flex';
  end if;


  -- ==========================================================
  -- 13. PLAN STATES
  -- ==========================================================

  if not exists (
    select 1
    from public.student_semester_plans
    where id =
          v_source_plan_id
      and status =
          'completed'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: source plan not completed';
  end if;


  if not exists (
    select 1
    from public.student_semester_plans
    where id =
          v_target_plan_id
      and status =
          'active'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: target flex plan not activated';
  end if;


  -- ==========================================================
  -- 14. OLD REGULAR SCHEDULE CLOSED AT BOUNDARY
  -- ==========================================================

  if not exists (
    select 1

    from public.regular_schedule_slots rs

    where rs.id =
          v_slot_id

      and rs.ends_on =
          date '2002-02-03'
  ) then

    raise exception
      'TEST_FAILED: regular logical slot not closed';
  end if;


  if not exists (
    select 1

    from public.lesson_series ls

    where ls.id =
          v_series_id

      and ls.effective_until =
          date '2002-02-03'
  ) then

    raise exception
      'TEST_FAILED: regular series not closed';
  end if;


  -- ==========================================================
  -- 15. SOURCE RIGHT FINALIZATION
  --
  -- canceled #1 becomes expired source
  -- #2-4 become consumed
  -- ==========================================================

  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_1

      and r.status =
          'expired'::public.lesson_right_status

      and r.expired_at is not null
  ) then

    raise exception
      'TEST_FAILED: carried source regular right not expired';
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_right_2,
    v_right_3,
    v_right_4
  )

    and r.status =
        'consumed'::public.lesson_right_status;


  if v_count <> 3 then
    raise exception
      'TEST_FAILED: source reserved regular rights not consumed';
  end if;


  -- ==========================================================
  -- 16. EXACTLY ONE REGULAR CARRYOVER
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.origin =
        'carryover'::public.lesson_right_origin

    and r.source_right_id =
        v_right_1

    and r.source_semester_id =
        v_source_semester_id

    and r.usable_semester_id =
        v_target_semester_id

    and r.duration_minutes = 30

    and r.status =
        'available'::public.lesson_right_status;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: expected exactly one regular carryover';
  end if;


  -- ==========================================================
  -- 17. TARGET FLEX BASE RIGHTS
  --
  -- 4 new flex rights + 1 carryover.
  -- Carryover is EXTRA, not one of the four.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.usable_semester_id =
        v_target_semester_id

    and r.origin =
        'flex_base'::public.lesson_right_origin

    and r.duration_minutes = 30;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: target flex plan expected 4 base rights, got %',
      v_count;
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.usable_semester_id =
        v_target_semester_id

    and r.status =
        'available'::public.lesson_right_status

    and r.origin in (
      'flex_base'::public.lesson_right_origin,
      'carryover'::public.lesson_right_origin
    );


  if v_count <> 5 then
    raise exception
      'TEST_FAILED: target expected 4 flex + 1 carryover = 5 available rights, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 18. HIGH-LEVEL AUDIT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_SEMESTER_TRANSITIONED'

    and a.subject_profile_id =
        v_student_id

    and a.semester_id =
        v_target_semester_id;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: expected exactly 1 transition audit, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 19. IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> false then
    raise exception
      'TEST_FAILED: repeated transition was not idempotent: %',
      v_result;
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.usable_semester_id =
        v_target_semester_id

    and r.origin =
        'carryover'::public.lesson_right_origin;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: idempotent transition duplicated carryover';
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.origin =
        'flex_base'::public.lesson_right_origin;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: idempotent transition duplicated flex base rights';
  end if;


  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_SEMESTER_TRANSITIONED'

    and a.subject_profile_id =
        v_student_id

    and a.semester_id =
        v_target_semester_id;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: idempotent transition duplicated audit';
  end if;

end;
$$;


select
  'PASS: regular-to-flex semester transition / boundary type change / source finalization / regular schedule closure / carryover extra entitlement / flex target activation / authorization / idempotency / audit'
  as test_result;

rollback;
