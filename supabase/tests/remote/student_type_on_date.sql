begin;

do $test$
declare
  v_branch_id uuid := gen_random_uuid();
  v_student_regular_id uuid := gen_random_uuid();
  v_student_flex_id uuid := gen_random_uuid();
  v_semester_a uuid := gen_random_uuid();
  v_semester_b uuid := gen_random_uuid();
  v_anchor date;
  v_result public.student_type;
  v_message text;
begin
  select greatest(
    date '2100-01-01',
    coalesce(max(s.ends_on) + 28, date '2100-01-01')
  )
  into v_anchor
  from public.semesters s;

  insert into public.branches (id, name)
  values (v_branch_id, 'ROLLBACK student_type_on_date fixture');

  insert into auth.users (id)
  values
    (v_student_regular_id),
    (v_student_flex_id);

  insert into public.profiles (
    id, display_name, role, branch_id, is_active
  ) values
    (
      v_student_regular_id,
      'Rollback Regular Student',
      'student'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_flex_id,
      'Rollback Flex Student',
      'student'::public.user_role,
      v_branch_id,
      true
    );

  insert into public.students (
    id, status, student_type
  ) values
    (
      v_student_regular_id,
      'active'::public.student_status,
      'regular'::public.student_type
    ),
    (
      v_student_flex_id,
      'active'::public.student_status,
      'flex'::public.student_type
    );

  insert into public.semesters (
    id, code, starts_on, ends_on
  ) values
    (
      v_semester_a,
      'ROLLBACK-A-' || replace(v_semester_a::text, '-', ''),
      v_anchor,
      v_anchor + 27
    ),
    (
      v_semester_b,
      'ROLLBACK-B-' || replace(v_semester_b::text, '-', ''),
      v_anchor + 35,
      v_anchor + 62
    );

  -- Make the branch-effective ranges overlap without violating
  -- the global semesters exclusion constraint.
  insert into public.branch_semester_overrides (
    branch_id, semester_id, starts_on, ends_on
  ) values
    (
      v_branch_id,
      v_semester_a,
      v_anchor + 7,
      v_anchor + 34
    ),
    (
      v_branch_id,
      v_semester_b,
      v_anchor + 14,
      v_anchor + 41
    );

  -- 1. No matching plan -> current students.student_type fallback.
  v_result := private.student_type_on_date(
    v_student_regular_id,
    v_anchor - 1
  );

  if v_result <> 'regular'::public.student_type then
    raise exception 'TEST_FAIL fallback expected regular, got %', v_result;
  end if;

  -- 2. Current regular + future FLEX planned plan -> flex.
  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status
  ) values (
    v_student_regular_id,
    v_semester_a,
    v_branch_id,
    'flex'::public.student_type,
    4,
    30,
    'planned'::public.student_semester_plan_status
  );

  v_result := private.student_type_on_date(
    v_student_regular_id,
    v_anchor + 8
  );

  if v_result <> 'flex'::public.student_type then
    raise exception 'TEST_FAIL planned future flex expected flex, got %', v_result;
  end if;

  -- Status is lifecycle metadata, not type validity.
  update public.student_semester_plans
  set status = 'active'::public.student_semester_plan_status
  where student_id = v_student_regular_id
    and semester_id = v_semester_a;

  v_result := private.student_type_on_date(
    v_student_regular_id,
    v_anchor + 8
  );

  if v_result <> 'flex'::public.student_type then
    raise exception 'TEST_FAIL active plan expected flex, got %', v_result;
  end if;

  update public.student_semester_plans
  set status = 'completed'::public.student_semester_plan_status
  where student_id = v_student_regular_id
    and semester_id = v_semester_a;

  v_result := private.student_type_on_date(
    v_student_regular_id,
    v_anchor + 8
  );

  if v_result <> 'flex'::public.student_type then
    raise exception 'TEST_FAIL completed plan expected flex, got %', v_result;
  end if;

  -- 3. Current flex + future REGULAR planned plan -> regular.
  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status
  ) values (
    v_student_flex_id,
    v_semester_a,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status
  );

  v_result := private.student_type_on_date(
    v_student_flex_id,
    v_anchor + 8
  );

  if v_result <> 'regular'::public.student_type then
    raise exception 'TEST_FAIL planned future regular expected regular, got %', v_result;
  end if;

  -- 4. Two effective plans on the same date must fail closed.
  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status
  ) values (
    v_student_regular_id,
    v_semester_b,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status
  );

  begin
    perform private.student_type_on_date(
      v_student_regular_id,
      v_anchor + 20
    );

    raise exception 'TEST_FAIL ambiguous effective plans did not fail';
  exception
    when others then
      get stacked diagnostics v_message = message_text;

      if v_message <> 'FORESTRING_AMBIGUOUS_STUDENT_SEMESTER_PLAN_ON_DATE' then
        raise exception 'TEST_FAIL unexpected ambiguity error: %', v_message;
      end if;
  end;
end;
$test$;

rollback;
