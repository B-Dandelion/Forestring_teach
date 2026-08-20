begin;

do $$
declare
  v_manager_id uuid;
  v_manager_branch_id uuid;

  v_other_manager_id uuid;

  v_student_id uuid;

  v_semester_id uuid;
  v_semester_start date;

  v_plan_id uuid;

  v_result jsonb;

  v_count integer;
  v_cross_branch_denied boolean := false;
begin

  -- ==========================================================
  -- 1. SAME-BRANCH MANAGER FIXTURE
  -- ==========================================================

  select
    p.id,
    p.branch_id
  into
    v_manager_id,
    v_manager_branch_id
  from public.profiles p
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
  order by p.created_at
  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active manager';
  end if;


  -- ==========================================================
  -- 2. ACTIVE STUDENT IN MANAGER BRANCH
  -- ==========================================================

  select p.id
  into v_student_id
  from public.profiles p
  join public.students s
    on s.id = p.id
  where p.role = 'student'::public.user_role
    and p.is_active = true
    and p.branch_id = v_manager_branch_id
    and s.status = 'active'::public.student_status
  order by p.created_at
  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active same-branch student';
  end if;


  -- ==========================================================
  -- 3. MANAGER FROM ANOTHER BRANCH
  -- ==========================================================

  select p.id
  into v_other_manager_id
  from public.profiles p
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
    and p.branch_id <> v_manager_branch_id
  order by p.created_at
  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 4. TEMP TEST SEMESTER
  --
  -- Put it immediately after the latest existing semester so
  -- the global no-overlap constraint is respected.
  -- 28 inclusive days = 4 complete weeks.
  -- ==========================================================

  select
    coalesce(
      max(s.ends_on),
      current_date
    ) + 1
  into v_semester_start
  from public.semesters s;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FLEX-' ||
      replace(
        gen_random_uuid()::text,
        '-',
        ''
      ),

    v_semester_start,

    v_semester_start + 27
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 5. ACTIVE FLEX PLAN
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
    v_semester_id,
    v_manager_branch_id,
    'flex'::public.student_type,
    8,
    30,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_plan_id;


  -- ==========================================================
  -- 6. SIMULATE SAME-BRANCH MANAGER JWT
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
  -- 7. FIRST MATERIALIZATION
  -- ==========================================================

  v_result :=
    public.materialize_flex_base_rights(
      v_plan_id
    );


  if (v_result ->> 'insertedCount')::integer <> 8 then
    raise exception
      'TEST_FAILED: first insertedCount expected 8, got %',
      v_result ->> 'insertedCount';
  end if;


  if (v_result ->> 'totalCount')::integer <> 8 then
    raise exception
      'TEST_FAILED: first totalCount expected 8, got %',
      v_result ->> 'totalCount';
  end if;


  -- ==========================================================
  -- 8. VERIFY EXACT RIGHTS
  -- ==========================================================

  select count(*)::integer
  into v_count
  from public.lesson_rights r
  where r.student_id = v_student_id
    and r.source_semester_id = v_semester_id
    and r.usable_semester_id = v_semester_id
    and r.branch_id = v_manager_branch_id
    and r.origin =
        'flex_base'::public.lesson_right_origin
    and r.status =
        'available'::public.lesson_right_status
    and r.duration_minutes = 30
    and r.sequence_no between 1 and 8;


  if v_count <> 8 then
    raise exception
      'TEST_FAILED: expected exactly 8 valid flex rights, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 9. IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.materialize_flex_base_rights(
      v_plan_id
    );


  if (v_result ->> 'insertedCount')::integer <> 0 then
    raise exception
      'TEST_FAILED: second insertedCount expected 0, got %',
      v_result ->> 'insertedCount';
  end if;


  if (v_result ->> 'totalCount')::integer <> 8 then
    raise exception
      'TEST_FAILED: second totalCount expected 8, got %',
      v_result ->> 'totalCount';
  end if;


  -- ==========================================================
  -- 10. CROSS-BRANCH MANAGER MUST FAIL
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


  begin

    perform public.materialize_flex_base_rights(
      v_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then

        v_cross_branch_denied := true;

      else
        raise;
      end if;

  end;


  if not v_cross_branch_denied then
    raise exception
      'TEST_FAILED: cross-branch manager was not denied';
  end if;


  raise notice
    'PASS: flex rights materialization / idempotency / branch permission';

end;
$$;

rollback;
