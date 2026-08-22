begin;

do $test$
declare
  v_actor_id uuid := gen_random_uuid();
  v_old_teacher_id uuid := gen_random_uuid();
  v_new_teacher_id uuid := gen_random_uuid();
  v_student_future_flex uuid := gen_random_uuid();
  v_student_future_regular uuid := gen_random_uuid();
  v_student_fallback uuid := gen_random_uuid();
  v_branch_id uuid := gen_random_uuid();
  v_semester_id uuid := gen_random_uuid();
  v_effective_on date;
  v_slot_future_flex uuid := gen_random_uuid();
  v_slot_future_regular uuid := gen_random_uuid();
  v_slot_fallback uuid := gen_random_uuid();
  v_result jsonb;
  v_teacher_id uuid;
begin
  select greatest(
    ((pg_catalog.now() at time zone 'Asia/Seoul')::date + 90),
    coalesce(
      max(s.ends_on) + 35,
      ((pg_catalog.now() at time zone 'Asia/Seoul')::date + 90)
    )
  )
  into v_effective_on
  from public.semesters s;

  insert into public.branches (id, name)
  values (
    v_branch_id,
    'ROLLBACK date-aware teacher change ' || left(v_branch_id::text, 8)
  );

  insert into auth.users (id)
  values
    (v_actor_id),
    (v_old_teacher_id),
    (v_new_teacher_id),
    (v_student_future_flex),
    (v_student_future_regular),
    (v_student_fallback);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values
    (
      v_actor_id,
      'Rollback Master',
      'master'::public.user_role,
      null,
      true
    ),
    (
      v_old_teacher_id,
      'Rollback Old Teacher',
      'teacher'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_new_teacher_id,
      'Rollback New Teacher',
      'teacher'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_future_flex,
      'Rollback Future Flex',
      'student'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_future_regular,
      'Rollback Future Regular',
      'student'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_fallback,
      'Rollback Fallback',
      'student'::public.user_role,
      v_branch_id,
      true
    );

  insert into public.teachers (id)
  values
    (v_old_teacher_id),
    (v_new_teacher_id);

  insert into public.students (
    id,
    status,
    student_type
  )
  values
    (
      v_student_future_flex,
      'active'::public.student_status,
      'regular'::public.student_type
    ),
    (
      v_student_future_regular,
      'active'::public.student_status,
      'flex'::public.student_type
    ),
    (
      v_student_fallback,
      'active'::public.student_status,
      'regular'::public.student_type
    );

  insert into public.semesters (
    id,
    code,
    starts_on,
    ends_on
  )
  values (
    v_semester_id,
    'ROLLBACK-DATE-AWARE-' ||
      replace(v_semester_id::text, '-', ''),
    v_effective_on,
    v_effective_on + 27
  );

  -- Case 1:
  -- current regular + future flex plan
  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status
  )
  values (
    v_student_future_flex,
    v_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    4,
    30,
    'planned'::public.student_semester_plan_status
  );

  -- Case 2:
  -- current flex + future regular plan
  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status
  )
  values (
    v_student_future_regular,
    v_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status
  );

  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values
    (
      v_old_teacher_id,
      1,
      time '09:00',
      time '18:00'
    ),
    (
      v_new_teacher_id,
      1,
      time '09:00',
      time '18:00'
    );

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values
    (
      v_old_teacher_id,
      v_student_future_flex,
      v_effective_on - 30,
      null
    ),
    (
      v_old_teacher_id,
      v_student_future_regular,
      v_effective_on - 30,
      null
    ),
    (
      v_old_teacher_id,
      v_student_fallback,
      v_effective_on - 30,
      null
    );

  insert into public.regular_schedule_slots (
    id,
    student_id,
    branch_id,
    starts_on,
    ends_on,
    created_by
  )
  values
    (
      v_slot_future_flex,
      v_student_future_flex,
      v_branch_id,
      v_effective_on - 30,
      null,
      v_actor_id
    ),
    (
      v_slot_future_regular,
      v_student_future_regular,
      v_branch_id,
      v_effective_on,
      null,
      v_actor_id
    ),
    (
      v_slot_fallback,
      v_student_fallback,
      v_branch_id,
      v_effective_on - 30,
      null,
      v_actor_id
    );

  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    effective_until,
    branch_id,
    schedule_slot_id
  )
  values
    (
      v_student_future_flex,
      v_old_teacher_id,
      1,
      time '10:00',
      30,
      v_effective_on,
      null,
      v_branch_id,
      v_slot_future_flex
    ),
    (
      v_student_future_regular,
      v_old_teacher_id,
      1,
      time '11:00',
      30,
      v_effective_on,
      null,
      v_branch_id,
      v_slot_future_regular
    ),
    (
      v_student_fallback,
      v_old_teacher_id,
      1,
      time '12:00',
      30,
      v_effective_on,
      null,
      v_branch_id,
      v_slot_fallback
    );

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_actor_id::text,
    true
  );

  perform pg_catalog.set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  -- ==========================================================
  -- 1. CURRENT REGULAR + FUTURE FLEX
  --
  -- Assignment must change, but recurring regular schedule
  -- must NOT be re-versioned.
  -- ==========================================================

  v_result := public.change_student_teacher(
    v_student_future_flex,
    v_new_teacher_id,
    v_effective_on
  );

  if v_result ->> 'studentType' <> 'flex' then
    raise exception
      'TEST_FAIL future flex expected studentType=flex, got %',
      v_result;
  end if;

  if coalesce(
    (v_result ->> 'regularScheduleChangeCount')::integer,
    -1
  ) <> 0 then
    raise exception
      'TEST_FAIL future flex expected 0 regular schedule changes, got %',
      v_result;
  end if;

  select ls.teacher_id
  into v_teacher_id
  from public.lesson_series ls
  where ls.schedule_slot_id = v_slot_future_flex
    and ls.effective_from <= v_effective_on
    and (
      ls.effective_until is null
      or ls.effective_until >= v_effective_on
    );

  if v_teacher_id <> v_old_teacher_id then
    raise exception
      'TEST_FAIL future flex series was unexpectedly re-versioned';
  end if;

  -- ==========================================================
  -- 2. CURRENT FLEX + FUTURE REGULAR
  --
  -- Future regular plan must cause the recurring schedule
  -- to move to the new teacher.
  -- ==========================================================

  v_result := public.change_student_teacher(
    v_student_future_regular,
    v_new_teacher_id,
    v_effective_on
  );

  if v_result ->> 'studentType' <> 'regular' then
    raise exception
      'TEST_FAIL future regular expected studentType=regular, got %',
      v_result;
  end if;

  if coalesce(
    (v_result ->> 'regularScheduleChangeCount')::integer,
    -1
  ) <> 1 then
    raise exception
      'TEST_FAIL future regular expected 1 regular schedule change, got %',
      v_result;
  end if;

  select ls.teacher_id
  into v_teacher_id
  from public.lesson_series ls
  where ls.schedule_slot_id = v_slot_future_regular
    and ls.effective_from <= v_effective_on
    and (
      ls.effective_until is null
      or ls.effective_until >= v_effective_on
    );

  if v_teacher_id <> v_new_teacher_id then
    raise exception
      'TEST_FAIL future regular series did not move to new teacher';
  end if;

  -- ==========================================================
  -- 3. NO PLAN ON EFFECTIVE DATE
  --
  -- Must fall back to current students.student_type.
  -- ==========================================================

  v_result := public.change_student_teacher(
    v_student_fallback,
    v_new_teacher_id,
    v_effective_on
  );

  if v_result ->> 'studentType' <> 'regular' then
    raise exception
      'TEST_FAIL fallback expected studentType=regular, got %',
      v_result;
  end if;

  if coalesce(
    (v_result ->> 'regularScheduleChangeCount')::integer,
    -1
  ) <> 1 then
    raise exception
      'TEST_FAIL fallback regular expected 1 regular schedule change, got %',
      v_result;
  end if;

  select ls.teacher_id
  into v_teacher_id
  from public.lesson_series ls
  where ls.schedule_slot_id = v_slot_fallback
    and ls.effective_from <= v_effective_on
    and (
      ls.effective_until is null
      or ls.effective_until >= v_effective_on
    );

  if v_teacher_id <> v_new_teacher_id then
    raise exception
      'TEST_FAIL fallback regular series did not move to new teacher';
  end if;
end;
$test$;

rollback;
