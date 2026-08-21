begin;

do $$
declare
  v_manager_id uuid;
  v_other_manager_id uuid;

  v_branch_id uuid;

  v_teacher_a_id uuid;
  v_teacher_b_id uuid;

  v_regular_student_id uuid;
  v_flex_student_id uuid;

  v_regular_semester_id uuid;
  v_flex_semester_id uuid;

  v_regular_plan_id uuid;
  v_flex_plan_id uuid;

  v_regular_slot_id uuid;
  v_regular_old_series_id uuid;

  v_regular_right_1 uuid;
  v_regular_right_2 uuid;
  v_regular_right_3 uuid;
  v_regular_right_4 uuid;

  v_regular_lesson_1 uuid;
  v_regular_lesson_2 uuid;
  v_regular_lesson_3 uuid;
  v_regular_lesson_4 uuid;

  v_flex_available_right_id uuid;
  v_flex_reserved_right_id uuid;
  v_flex_existing_lesson_id uuid;

  v_regular_old_assignment_id uuid;
  v_regular_new_assignment_id uuid;

  v_flex_old_assignment_id uuid;
  v_flex_new_assignment_id uuid;

  v_effective_on date :=
    date '2102-01-17';

  v_flex_effective_on date :=
    date '2102-03-01';

  v_result jsonb;

  v_count integer;
  v_denied boolean;

begin

  -- ==========================================================
  -- 1. MAIN FIXTURE
  --
  -- teacher A = normal teacher
  -- teacher B = manager (all managers have teachers row)
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
    v_regular_student_id

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


  v_teacher_b_id :=
    v_manager_id;


  -- ==========================================================
  -- 2. SECOND STUDENT FOR FLEX
  -- ==========================================================

  select p.id
  into v_flex_student_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id <>
        v_regular_student_id

  order by
    case
      when p.branch_id = v_branch_id
        then 0
      else 1
    end,
    p.created_at

  limit 1;


  if v_flex_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second student';
  end if;


  update public.profiles
  set
    branch_id = v_branch_id,
    is_active = true

  where id =
        v_flex_student_id;


  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null,

    student_type =
      'flex'::public.student_type

  where id =
        v_flex_student_id;


  update public.students
  set
    student_type =
      'regular'::public.student_type

  where id =
        v_regular_student_id;


  -- ==========================================================
  -- 3. CROSS-BRANCH MANAGER
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
      'TEST_FIXTURE_REQUIRED: other branch manager';
  end if;


  -- ==========================================================
  -- 4. CLEAN SYNTHETIC ASSIGNMENTS
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id in (
    v_regular_student_id,
    v_flex_student_id
  )

    and starts_on >=
        date '2101-12-01';


  update public.teacher_student_assignments
  set
    ends_on =
      date '2101-11-30'

  where student_id in (
    v_regular_student_id,
    v_flex_student_id
  )

    and starts_on <=
        date '2101-11-30'

    and (
      ends_on is null
      or ends_on >
         date '2101-11-30'
    );


  -- ==========================================================
  -- 5. WORK HOURS
  --
  -- Initially only teacher A has suitable hours.
  -- This lets us prove failed reassignment rolls back.
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
      1,
      time '17:00',
      time '21:00'
    );


  -- ==========================================================
  -- 6. REGULAR SEMESTER
  --
  -- 2102-01-02 is Monday.
  -- Mondays:
  --   01/02
  --   01/09
  --   01/16
  --   01/23
  --
  -- Change effective 01/17:
  -- only the fourth untouched lesson lies after the change.
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-TEACHER-CHANGE-REGULAR-2102',
    date '2102-01-02',
    date '2102-01-29'
  )
  returning id
  into v_regular_semester_id;


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
    v_regular_student_id,
    v_regular_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_regular_plan_id;


  -- ==========================================================
  -- 7. REGULAR ASSIGNMENT A
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_a_id,
    v_regular_student_id,
    date '2101-12-01',
    null
  )
  returning id
  into v_regular_old_assignment_id;


  -- ==========================================================
  -- 8. REGULAR SLOT / SERIES A
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_regular_student_id,
    v_branch_id,
    date '2101-12-01',
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
    branch_id,
    schedule_slot_id
  )
  values (
    v_regular_student_id,
    v_teacher_a_id,
    1,
    time '18:00',
    30,
    date '2101-12-01',
    v_branch_id,
    v_regular_slot_id
  )
  returning id
  into v_regular_old_series_id;


  -- ==========================================================
  -- 9. REGULAR RIGHTS
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
      v_regular_student_id,
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
      v_regular_student_id,
      v_branch_id,
      v_regular_semester_id,
      v_regular_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      2,
      30,
      'available'::public.lesson_right_status,
      v_manager_id,
      null
    ),
    (
      v_regular_student_id,
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
    ),
    (
      v_regular_student_id,
      v_branch_id,
      v_regular_semester_id,
      v_regular_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      4,
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

  select id into v_regular_right_4
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_regular_semester_id
    and sequence_no = 4;


  -- ==========================================================
  -- 10. REGULAR LESSONS
  --
  -- #1 untouched but BEFORE change date
  -- #2 canceled
  -- #3 individually moved
  -- #4 untouched AFTER change date
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
    rescheduled_by,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values
    (
      v_regular_old_series_id,
      v_regular_student_id,
      v_teacher_a_id,
      v_branch_id,
      timestamptz '2102-01-02 18:00:00+09',
      timestamptz '2102-01-02 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_1,
      null,
      null,
      null,
      null
    ),
    (
      v_regular_old_series_id,
      v_regular_student_id,
      v_teacher_a_id,
      v_branch_id,
      timestamptz '2102-01-09 18:00:00+09',
      timestamptz '2102-01-09 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_regular_right_2,
      null,
      v_regular_student_id,
      timestamptz '2102-01-08 12:00:00+09',
      'teacher change test'
    ),
    (
      v_regular_old_series_id,
      v_regular_student_id,
      v_teacher_a_id,
      v_branch_id,
      timestamptz '2102-01-16 18:00:00+09',
      timestamptz '2102-01-18 20:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_3,
      v_manager_id,
      null,
      null,
      null
    ),
    (
      v_regular_old_series_id,
      v_regular_student_id,
      v_teacher_a_id,
      v_branch_id,
      timestamptz '2102-01-23 18:00:00+09',
      timestamptz '2102-01-23 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_4,
      null,
      null,
      null,
      null
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

  select id into v_regular_lesson_4
  from public.lessons
  where lesson_right_id = v_regular_right_4;


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
    v_regular_lesson_2,
    v_regular_right_2,
    v_regular_student_id,
    v_branch_id,
    'student'::public.lesson_cancellation_origin,
    v_regular_student_id,
    true,
    timestamptz '2102-01-08 12:00:00+09',
    'teacher change test'
  );


  -- ==========================================================
  -- 11. LOGIN AS MANAGER
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
  -- 12. FIRST TRY MUST FAIL
  --
  -- Teacher B has no Monday work hours.
  --
  -- Assignment mutation occurs first internally, then regular
  -- reconciliation fails. The WHOLE RPC must rollback.
  -- ==========================================================

  v_denied := false;


  begin

    perform public.change_student_teacher(
      v_regular_student_id,
      v_teacher_b_id,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher change succeeded without target work hours';
  end if;


  if not exists (
    select 1

    from public.teacher_student_assignments a

    where a.id =
          v_regular_old_assignment_id

      and a.teacher_id =
          v_teacher_a_id

      and a.ends_on is null
  ) then

    raise exception
      'TEST_FAILED: failed teacher change partially closed old assignment';
  end if;


  if exists (
    select 1

    from public.teacher_student_assignments a

    where a.student_id =
          v_regular_student_id

      and a.teacher_id =
          v_teacher_b_id

      and a.starts_on =
          v_effective_on
  ) then

    raise exception
      'TEST_FAILED: failed teacher change left new assignment';
  end if;


  -- ==========================================================
  -- 13. GIVE TEACHER B VALID HOURS
  -- ==========================================================

  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_b_id,
    1,
    time '17:00',
    time '21:00'
  );


  -- ==========================================================
  -- 14. SUCCESSFUL REGULAR TEACHER CHANGE
  -- ==========================================================

  v_result :=
    public.change_student_teacher(
      v_regular_student_id,
      v_teacher_b_id,
      v_effective_on
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: regular teacher change returned changed=false';
  end if;


  if (v_result ->> 'regularSlotCount')::integer <> 1
     or
     (v_result ->> 'regularScheduleChangeCount')::integer <> 1 then

    raise exception
      'TEST_FAILED: regular schedule propagation incorrect: %',
      v_result;
  end if;


  v_regular_new_assignment_id :=
    (
      v_result
      ->> 'assignmentId'
    )::uuid;


  -- ==========================================================
  -- 15. ASSIGNMENT HISTORY
  -- ==========================================================

  if not exists (
    select 1

    from public.teacher_student_assignments a

    where a.id =
          v_regular_old_assignment_id

      and a.teacher_id =
          v_teacher_a_id

      and a.ends_on =
          v_effective_on - 1
  ) then

    raise exception
      'TEST_FAILED: old regular assignment end date incorrect';
  end if;


  if not exists (
    select 1

    from public.teacher_student_assignments a

    where a.id =
          v_regular_new_assignment_id

      and a.teacher_id =
          v_teacher_b_id

      and a.student_id =
          v_regular_student_id

      and a.branch_id =
          v_branch_id

      and a.starts_on =
          v_effective_on

      and a.ends_on is null
  ) then

    raise exception
      'TEST_FAILED: new regular assignment incorrect';
  end if;


  -- ==========================================================
  -- 16. SERIES VERSIONED TO B
  -- ==========================================================

  if not exists (
    select 1

    from public.lesson_series ls

    where ls.schedule_slot_id =
          v_regular_slot_id

      and ls.teacher_id =
          v_teacher_a_id

      and ls.effective_until =
          v_effective_on - 1
  ) then

    raise exception
      'TEST_FAILED: teacher A series was not closed';
  end if;


  if not exists (
    select 1

    from public.lesson_series ls

    where ls.schedule_slot_id =
          v_regular_slot_id

      and ls.teacher_id =
          v_teacher_b_id

      and ls.effective_from =
          v_effective_on

      and ls.weekday = 1

      and ls.start_time =
          time '18:00'

      and ls.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: teacher B series version missing';
  end if;


  -- ==========================================================
  -- 17. BEFORE EFFECTIVE DATE REMAINS A
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_regular_lesson_1

      and l.teacher_id =
          v_teacher_a_id

      and l.starts_at =
          timestamptz '2102-01-02 18:00:00+09'
  ) then

    raise exception
      'TEST_FAILED: pre-effective lesson changed teacher';
  end if;


  -- ==========================================================
  -- 18. CANCELED REMAINS A
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_regular_lesson_2

      and l.teacher_id =
          v_teacher_a_id

      and l.status =
          'canceled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: canceled lesson changed teacher';
  end if;


  -- ==========================================================
  -- 19. INDIVIDUALLY MOVED REMAINS A
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_regular_lesson_3

      and l.teacher_id =
          v_teacher_a_id

      and l.starts_at =
          timestamptz '2102-01-18 20:00:00+09'

      and l.rescheduled_by =
          v_manager_id
  ) then

    raise exception
      'TEST_FAILED: individually moved lesson changed teacher';
  end if;


  -- ==========================================================
  -- 20. UNTOUCHED FUTURE LESSON B
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_regular_lesson_4

      and l.lesson_right_id =
          v_regular_right_4

      and l.occurrence_at =
          timestamptz '2102-01-23 18:00:00+09'

      and l.starts_at =
          timestamptz '2102-01-23 18:00:00+09'

      and l.teacher_id =
          v_teacher_b_id

      and l.rescheduled_by is null
  ) then

    raise exception
      'TEST_FAILED: untouched future regular lesson did not move to B';
  end if;


  -- ==========================================================
  -- 21. NO-OP SAME TEACHER
  -- ==========================================================

  v_result :=
    public.change_student_teacher(
      v_regular_student_id,
      v_teacher_b_id,
      v_effective_on
    );


  if (v_result ->> 'changed')::boolean <> false then
    raise exception
      'TEST_FAILED: same teacher reassignment was not no-op';
  end if;


  -- ==========================================================
  -- 22. FLEX SEMESTER / ASSIGNMENT
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-TEACHER-CHANGE-FLEX-2102',
    date '2102-03-01',
    date '2102-03-28'
  )
  returning id
  into v_flex_semester_id;


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
    v_flex_student_id,
    v_flex_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    4,
    30,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_flex_plan_id;


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_a_id,
    v_flex_student_id,
    date '2102-02-01',
    null
  )
  returning id
  into v_flex_old_assignment_id;


  -- ==========================================================
  -- 23. FLEX AVAILABLE + EXISTING BOOKED RIGHT
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
    v_flex_student_id,
    v_branch_id,
    v_flex_semester_id,
    v_flex_semester_id,
    'flex_base'::public.lesson_right_origin,
    1,
    30,
    'available'::public.lesson_right_status,
    v_manager_id
  )
  returning id
  into v_flex_available_right_id;


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
    v_flex_student_id,
    v_branch_id,
    v_flex_semester_id,
    v_flex_semester_id,
    'flex_base'::public.lesson_right_origin,
    2,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    now()
  )
  returning id
  into v_flex_reserved_right_id;


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
    v_flex_student_id,
    v_teacher_a_id,
    v_branch_id,
    timestamptz '2102-03-08 18:00:00+09',
    30,
    'flex'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_flex_reserved_right_id
  )
  returning id
  into v_flex_existing_lesson_id;


  -- Teacher B needs availability for flex booking candidates.
  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_b_id,
    3,
    time '17:00',
    time '21:00'
  );


  -- ==========================================================
  -- 24. FLEX TEACHER CHANGE
  -- ==========================================================

  v_result :=
    public.change_student_teacher(
      v_flex_student_id,
      v_teacher_b_id,
      v_flex_effective_on
    );


  if (v_result ->> 'changed')::boolean <> true
     or
     (v_result ->> 'regularSlotCount')::integer <> 0
     or
     (v_result ->> 'regularScheduleChangeCount')::integer <> 0 then

    raise exception
      'TEST_FAILED: flex teacher change result incorrect: %',
      v_result;
  end if;


  v_flex_new_assignment_id :=
    (
      v_result
      ->> 'assignmentId'
    )::uuid;


  -- ==========================================================
  -- 25. FLEX ASSIGNMENT HISTORY
  -- ==========================================================

  if not exists (
    select 1
    from public.teacher_student_assignments a

    where a.id =
          v_flex_old_assignment_id

      and a.teacher_id =
          v_teacher_a_id

      and a.ends_on =
          v_flex_effective_on - 1
  ) then

    raise exception
      'TEST_FAILED: flex old assignment not closed';
  end if;


  if not exists (
    select 1
    from public.teacher_student_assignments a

    where a.id =
          v_flex_new_assignment_id

      and a.teacher_id =
          v_teacher_b_id

      and a.starts_on =
          v_flex_effective_on
  ) then

    raise exception
      'TEST_FAILED: flex new assignment missing';
  end if;


  -- ==========================================================
  -- 26. EXISTING FLEX BOOKING MUST STAY A
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_flex_existing_lesson_id

      and l.teacher_id =
          v_teacher_a_id

      and l.starts_at =
          timestamptz '2102-03-08 18:00:00+09'
  ) then

    raise exception
      'TEST_FAILED: existing flex booking was reassigned';
  end if;


  -- ==========================================================
  -- 27. FLEX NEW AVAILABILITY MUST USE B
  --
  -- 2102-03-15 is Wednesday.
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_flex_student_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_flex_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  if not exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_flex_available_right_id,
      date '2102-03-15'
    ) option_row

    where option_row.teacher_id =
          v_teacher_b_id
  ) then

    raise exception
      'TEST_FAILED: flex availability did not switch to B';
  end if;


  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_flex_available_right_id,
      date '2102-03-15'
    ) option_row

    where option_row.teacher_id <>
          v_teacher_b_id
  ) then

    raise exception
      'TEST_FAILED: flex availability still exposed old teacher';
  end if;


  -- ==========================================================
  -- 28. CROSS-BRANCH MANAGER DENIED
  -- ==========================================================

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

    perform public.change_student_teacher(
      v_regular_student_id,
      v_teacher_a_id,
      date '2102-02-01'
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
      'TEST_FAILED: cross-branch manager changed teacher';
  end if;


  -- ==========================================================
  -- 29. AUDIT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_TEACHER_CHANGED'

    and a.subject_profile_id in (
      v_regular_student_id,
      v_flex_student_id
    );


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: expected 2 teacher-change audits, got %',
      v_count;
  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_TEACHER_CHANGED'

      and a.subject_profile_id =
          v_regular_student_id

      and a.details ->> 'previousTeacherId' =
          v_teacher_a_id::text

      and a.details ->> 'newTeacherId' =
          v_teacher_b_id::text

      and (
        a.details
        ->> 'regularScheduleChangeCount'
      )::integer = 1
  ) then

    raise exception
      'TEST_FAILED: regular teacher-change audit incorrect';
  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_TEACHER_CHANGED'

      and a.subject_profile_id =
          v_flex_student_id

      and (
        a.details
        ->> 'regularScheduleChangeCount'
      )::integer = 0
  ) then

    raise exception
      'TEST_FAILED: flex teacher-change audit incorrect';
  end if;

end;
$$;


select
  'PASS: student teacher change / effective-date assignment history / regular series propagation / untouched future teacher reconcile / canceled+individual preserved / atomic rollback / flex existing booking preserved / flex future availability new teacher / branch auth / no-op / audit'
  as test_result;

rollback;
