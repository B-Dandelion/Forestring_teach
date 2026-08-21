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

  v_reserved_lesson_id uuid;

  v_result jsonb;

  v_count integer;
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
      'flex'::public.student_type,

    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_student_id;


  -- ==========================================================
  -- 2. CONSECUTIVE PAST SEMESTERS
  --
  -- source:
  --   2003-01-06 ~ 2003-02-02
  --
  -- target:
  --   2003-02-03 ~ 2003-03-02
  --
  -- Both begin Monday.
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FLEX-TO-REGULAR-SOURCE-2003',
    date '2003-01-06',
    date '2003-02-02'
  )
  returning id
  into v_source_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FLEX-TO-REGULAR-TARGET-2003',
    date '2003-02-03',
    date '2003-03-02'
  )
  returning id
  into v_target_semester_id;


  -- ==========================================================
  -- 3. SOURCE FLEX PLAN
  --
  -- N=4
  -- cancellation/carryover cap = floor(4/4) = 1
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
    v_source_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    4,
    30,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_source_plan_id;


  -- ==========================================================
  -- 4. TARGET REGULAR PLAN
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
    v_target_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_target_plan_id;


  -- ==========================================================
  -- 5. TEACHER ASSIGNMENT
  --
  -- Assignment already covers the future regular semester.
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
    date '2002-12-01',
    date '2003-03-02'
  );


  -- ==========================================================
  -- 6. TEMPORARY WORK HOURS FOR FIXTURE
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id =
        v_teacher_id;


  delete from public.blocked_periods
  where teacher_id =
        v_teacher_id;


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_id,
    1,
    time '17:00',
    time '21:00'
  );


  -- ==========================================================
  -- 7. PRECONFIGURE TARGET REGULAR SCHEDULE
  --
  -- Important:
  -- student is STILL flex right now.
  --
  -- But next semester regular configuration must be allowed to
  -- exist before the semester boundary.
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
    date '2003-02-03',
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
    date '2003-02-03',
    v_branch_id,
    v_slot_id
  )
  returning id
  into v_series_id;


  -- ==========================================================
  -- 8. SOURCE FLEX RIGHTS
  --
  -- #1 available  -> carryover candidate
  -- #2 available  -> expires
  -- #3 consumed   -> remains consumed
  -- #4 reserved   -> scheduled past lesson -> consumed
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
    v_student_id,
    v_branch_id,
    v_source_semester_id,
    v_source_semester_id,
    'flex_base'::public.lesson_right_origin,
    1,
    30,
    'available'::public.lesson_right_status,
    v_manager_id
  )
  returning id
  into v_right_1;


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
    v_student_id,
    v_branch_id,
    v_source_semester_id,
    v_source_semester_id,
    'flex_base'::public.lesson_right_origin,
    2,
    30,
    'available'::public.lesson_right_status,
    v_manager_id
  )
  returning id
  into v_right_2;


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
    consumed_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_source_semester_id,
    v_source_semester_id,
    'flex_base'::public.lesson_right_origin,
    3,
    30,
    'consumed'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2003-01-20 19:00:00+09'
  )
  returning id
  into v_right_3;


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
    v_student_id,
    v_branch_id,
    v_source_semester_id,
    v_source_semester_id,
    'flex_base'::public.lesson_right_origin,
    4,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2003-01-25 12:00:00+09'
  )
  returning id
  into v_right_4;


  -- ==========================================================
  -- 9. PAST RESERVED FLEX LESSON
  --
  -- Finalization should convert right #4 -> consumed.
  -- ==========================================================

  insert into public.lessons (
    student_id,
    teacher_id,
    branch_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values (
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2003-01-27 18:00:00+09',
    30,
    'flex'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_4
  )
  returning id
  into v_reserved_lesson_id;


  -- ==========================================================
  -- 10. LOGIN AS MANAGER
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
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
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 11. REMOVE TARGET WORK HOURS
  --
  -- transition does:
  --
  -- finalize source
  -- -> change student_type
  -- -> activate regular target
  --
  -- Target activation must now FAIL.
  --
  -- Everything before it must rollback.
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id =
        v_teacher_id;


  begin

    perform public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );


    raise exception
      'TEST_FAILED: transition unexpectedly succeeded without work hours';


  exception
    when others then

      if sqlerrm <>
         'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS' then

        raise;

      end if;

  end;


  -- ==========================================================
  -- 12. FAILURE MUST ROLLBACK SOURCE FINALIZATION
  -- ==========================================================

  if not exists (
    select 1

    from public.student_semester_plans sp

    where sp.id =
          v_source_plan_id

      and sp.status =
          'active'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: failed transition completed source plan';
  end if;


  if not exists (
    select 1

    from public.student_semester_plans sp

    where sp.id =
          v_target_plan_id

      and sp.status =
          'planned'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: failed transition activated target plan';
  end if;


  if not exists (
    select 1

    from public.students s

    where s.id =
          v_student_id

      and s.student_type =
          'flex'::public.student_type
  ) then

    raise exception
      'TEST_FAILED: failed transition changed current student type';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_1

      and r.status =
          'available'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: failed transition mutated source right #1';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_2

      and r.status =
          'available'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: failed transition mutated source right #2';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_4

      and r.status =
          'reserved'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: failed transition consumed reserved source right';
  end if;


  if exists (
    select 1

    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.origin =
          'carryover'::public.lesson_right_origin

      and r.usable_semester_id =
          v_target_semester_id
  ) then

    raise exception
      'TEST_FAILED: failed transition left carryover';
  end if;


  if exists (
    select 1

    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.source_semester_id =
          v_target_semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) then

    raise exception
      'TEST_FAILED: failed transition left target regular rights';
  end if;


  if exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_SEMESTER_TRANSITIONED'

      and a.subject_profile_id =
          v_student_id

      and a.semester_id =
          v_target_semester_id
  ) then

    raise exception
      'TEST_FAILED: failed transition left high-level audit';
  end if;


  -- ==========================================================
  -- 13. ENABLE VALID TARGET WORK HOURS
  -- ==========================================================

  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_id,
    1,
    time '17:00',
    time '21:00'
  );


  -- ==========================================================
  -- 14. SUCCESSFUL FLEX -> REGULAR TRANSITION
  -- ==========================================================

  v_result :=
    public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> true then

    raise exception
      'TEST_FAILED: successful transition returned changed=false: %',
      v_result;

  end if;


  if (v_result ->> 'studentTypeChanged')::boolean <> true
     or
     v_result ->> 'previousStudentType' <> 'flex'
     or
     v_result ->> 'studentType' <> 'regular' then

    raise exception
      'TEST_FAILED: flex-to-regular result type state incorrect: %',
      v_result;

  end if;


  if (v_result ->> 'closedRegularSlotCount')::integer <> 0
     or
     (v_result ->> 'closedRegularSeriesCount')::integer <> 0 then

    raise exception
      'TEST_FAILED: flex-to-regular unexpectedly closed regular schedules: %',
      v_result;

  end if;


  -- ==========================================================
  -- 15. CURRENT TYPE / PLAN STATES
  -- ==========================================================

  if not exists (
    select 1

    from public.students s

    where s.id =
          v_student_id

      and s.student_type =
          'regular'::public.student_type
  ) then

    raise exception
      'TEST_FAILED: student did not become regular';
  end if;


  if not exists (
    select 1

    from public.student_semester_plans sp

    where sp.id =
          v_source_plan_id

      and sp.status =
          'completed'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: source flex plan not completed';
  end if;


  if not exists (
    select 1

    from public.student_semester_plans sp

    where sp.id =
          v_target_plan_id

      and sp.status =
          'active'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: target regular plan not activated';
  end if;


  -- ==========================================================
  -- 16. SOURCE FLEX FINALIZATION
  --
  -- cap = 1
  --
  -- #1 -> carryover child + source expired
  -- #2 -> expired
  -- #3 -> consumed stays consumed
  -- #4 -> reserved past lesson -> consumed
  -- ==========================================================

  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_1

      and r.status =
          'expired'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: carried source flex right not expired';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_2

      and r.status =
          'expired'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: unused non-carried flex right not expired';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_3

      and r.status =
          'consumed'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: already-consumed source right changed';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_4

      and r.status =
          'consumed'::public.lesson_right_status

      and r.consumed_at is not null
  ) then

    raise exception
      'TEST_FAILED: past reserved flex right not consumed';
  end if;


  -- ==========================================================
  -- 17. EXACTLY ONE FLEX CARRYOVER
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
      'TEST_FAILED: expected exactly one flex carryover into regular target';

  end if;


  -- ==========================================================
  -- 18. TARGET REGULAR BASE RIGHTS
  --
  -- One logical slot -> exactly four.
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

    and r.schedule_slot_id =
        v_slot_id

    and r.origin =
        'regular_base'::public.lesson_right_origin

    and r.status =
        'reserved'::public.lesson_right_status;


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: target regular plan expected 4 reserved base rights, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 19. EXACTLY FOUR CANONICAL REGULAR LESSONS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lessons l

  join public.lesson_rights r
    on r.id =
       l.lesson_right_id

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.schedule_slot_id =
        v_slot_id

    and r.origin =
        'regular_base'::public.lesson_right_origin

    and l.lesson_type =
        'regular'::public.lesson_type

    and l.status =
        'scheduled'::public.lesson_status

    and l.teacher_id =
        v_teacher_id

    and l.duration_minutes = 30;


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: expected 4 target canonical regular lessons, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 20. EXACT TARGET OCCURRENCES
  --
  -- Mondays:
  -- 02/03
  -- 02/10
  -- 02/17
  -- 02/24
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lessons l

  join public.lesson_rights r
    on r.id =
       l.lesson_right_id

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.schedule_slot_id =
        v_slot_id

    and l.starts_at in (
      timestamptz '2003-02-03 18:00:00+09',
      timestamptz '2003-02-10 18:00:00+09',
      timestamptz '2003-02-17 18:00:00+09',
      timestamptz '2003-02-24 18:00:00+09'
    );


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: target regular occurrence dates incorrect';

  end if;


  -- ==========================================================
  -- 21. REGULAR CONFIGURATION REMAINS ACTIVE
  -- ==========================================================

  if not exists (
    select 1

    from public.regular_schedule_slots rs

    where rs.id =
          v_slot_id

      and rs.starts_on =
          date '2003-02-03'

      and rs.ends_on is null
  ) then

    raise exception
      'TEST_FAILED: target logical regular slot incorrect';
  end if;


  if not exists (
    select 1

    from public.lesson_series ls

    where ls.id =
          v_series_id

      and ls.schedule_slot_id =
          v_slot_id

      and ls.teacher_id =
          v_teacher_id

      and ls.weekday = 1

      and ls.start_time =
          time '18:00'

      and ls.duration_minutes = 30

      and ls.effective_from =
          date '2003-02-03'
  ) then

    raise exception
      'TEST_FAILED: target regular series incorrect';
  end if;


  -- ==========================================================
  -- 22. HIGH-LEVEL AUDIT
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
      'TEST_FAILED: expected exactly one transition audit, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 23. IDEMPOTENT SECOND CALL
  -- ==========================================================

  v_result :=
    public.transition_student_semester(
      v_source_plan_id,
      v_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> false then

    raise exception
      'TEST_FAILED: repeated flex-to-regular transition not idempotent: %',
      v_result;

  end if;


  -- Carryover still exactly one.
  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.origin =
        'carryover'::public.lesson_right_origin

    and r.usable_semester_id =
        v_target_semester_id;


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: idempotent transition duplicated carryover';

  end if;


  -- Regular rights still exactly four.
  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.schedule_slot_id =
        v_slot_id

    and r.origin =
        'regular_base'::public.lesson_right_origin;


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: idempotent transition duplicated regular rights';

  end if;


  -- Regular lessons still exactly four.
  select count(*)::integer
  into v_count

  from public.lessons l

  join public.lesson_rights r
    on r.id =
       l.lesson_right_id

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_target_semester_id

    and r.schedule_slot_id =
        v_slot_id

    and r.origin =
        'regular_base'::public.lesson_right_origin;


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: idempotent transition duplicated regular lessons';

  end if;


  -- High-level audit still one.
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
      'TEST_FAILED: idempotent transition duplicated transition audit';

  end if;

end;
$$;


select
  'PASS: flex-to-regular semester transition / atomic rollback on invalid target / source finalization / carryover / boundary type change / target regular materialization 4 rights+lessons / exact occurrences / idempotency / audit'
  as test_result;

rollback;
