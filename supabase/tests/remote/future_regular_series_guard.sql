begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;

  v_student_with_plan uuid;
  v_student_without_plan uuid;

  v_semester_id uuid;
  v_plan_id uuid;
  v_slot_id uuid;

  v_denied boolean := false;
begin

  -- ==========================================================
  -- 1. FIXTURE
  -- ==========================================================

  select
    mp.id,
    mp.branch_id,
    tp.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id

  from public.profiles mp

  join public.teachers mt
    on mt.id = mp.id

  join public.profiles tp
    on tp.branch_id = mp.branch_id
   and tp.role = 'teacher'::public.user_role
   and tp.is_active = true

  join public.teachers tt
    on tt.id = tp.id

  where mp.role = 'manager'::public.user_role
    and mp.is_active = true
    and mp.branch_id is not null

  limit 1;


  select p.id
  into v_student_with_plan

  from public.profiles p
  join public.students s
    on s.id = p.id

  where p.role = 'student'::public.user_role
    and p.is_active = true

  order by
    case when p.branch_id = v_branch_id then 0 else 1 end,
    p.created_at

  limit 1;


  select p.id
  into v_student_without_plan

  from public.profiles p
  join public.students s
    on s.id = p.id

  where p.role = 'student'::public.user_role
    and p.is_active = true
    and p.id <> v_student_with_plan

  order by
    case when p.branch_id = v_branch_id then 0 else 1 end,
    p.created_at

  limit 1;


  if v_manager_id is null
     or v_student_with_plan is null
     or v_student_without_plan is null then

    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + two students';

  end if;


  update public.profiles
  set branch_id = v_branch_id
  where id in (
    v_student_with_plan,
    v_student_without_plan
  );


  update public.students
  set
    student_type = 'flex'::public.student_type,
    status = 'active'::public.student_status,
    withdrawal_date = null
  where id in (
    v_student_with_plan,
    v_student_without_plan
  );


  -- ==========================================================
  -- 2. FUTURE REGULAR SEMESTER
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FUTURE-REGULAR-GUARD-2098',
    date '2098-01-06',
    date '2098-02-02'
  )
  returning id
  into v_semester_id;


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
    v_student_with_plan,
    v_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_plan_id;


  -- ==========================================================
  -- 3. WITH REGULAR PLAN -> ALLOWED
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_with_plan,
    v_branch_id,
    date '2098-01-06',
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
    v_student_with_plan,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2098-01-06',
    v_branch_id,
    v_slot_id
  );


  -- ==========================================================
  -- 4. FLEX WITHOUT REGULAR PLAN -> STILL DENIED
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_without_plan,
    v_branch_id,
    date '2098-01-06',
    v_manager_id
  )
  returning id
  into v_slot_id;


  begin

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
      v_student_without_plan,
      v_teacher_id,
      1,
      time '18:00',
      30,
      date '2098-01-06',
      v_branch_id,
      v_slot_id
    );


  exception
    when others then

      if sqlerrm =
         'FORESTRING_FLEX_STUDENT_CANNOT_HAVE_SERIES' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: arbitrary flex series was allowed';
  end if;

end;
$$;


select
  'PASS: future regular series preconfiguration / planned regular semester allowed / arbitrary flex series still denied'
  as test_result;

rollback;
