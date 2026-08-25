begin;

do $test$
declare
  v_master_id uuid := gen_random_uuid();
  v_manager_id uuid := gen_random_uuid();
  v_student_id uuid := gen_random_uuid();
  v_branch_id uuid := gen_random_uuid();
  v_other_branch_id uuid := gen_random_uuid();

  v_semester1_id uuid := gen_random_uuid();
  v_semester2_id uuid := gen_random_uuid();

  v_base_end date;
  v_s1_start date;
  v_s1_original_end date;
  v_s1_final_end date;
  v_s2_original_start date;
  v_s2_final_start date;
  v_s2_end date;

  v_message text;
  v_result jsonb;
  v_count integer;
begin
  -- ==========================================================
  -- STATIC PERMISSIONS
  -- ==========================================================

  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'upsert_semester',
      'delete_semester',
      'upsert_branch_semester_override',
      'delete_branch_semester_override',
      'upsert_closure_period',
      'delete_closure_period',
      'apply_semester_calendar_batch',
      'apply_branch_semester_overrides_batch'
    )
    and p.prosecdef = true
    and coalesce(p.proconfig, array[]::text[])
        @> array['search_path=""'];

  if v_count <> 8 then
    raise exception
      'TEST_FAIL expected 8 hardened public calendar RPCs, found %',
      v_count;
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'upsert_semester',
        'delete_semester',
        'upsert_branch_semester_override',
        'delete_branch_semester_override',
        'upsert_closure_period',
        'delete_closure_period',
        'apply_semester_calendar_batch',
        'apply_branch_semester_overrides_batch'
      )
      and (
        has_function_privilege(
          'public',
          p.oid,
          'EXECUTE'
        )
        or has_function_privilege(
          'anon',
          p.oid,
          'EXECUTE'
        )
      )
  ) then
    raise exception
      'TEST_FAIL public/anon can execute a calendar mutation RPC';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'upsert_semester',
        'delete_semester',
        'upsert_branch_semester_override',
        'delete_branch_semester_override',
        'upsert_closure_period',
        'delete_closure_period',
        'apply_semester_calendar_batch',
        'apply_branch_semester_overrides_batch'
      )
      and (
        not has_function_privilege(
          'authenticated',
          p.oid,
          'EXECUTE'
        )
        or not has_function_privilege(
          'service_role',
          p.oid,
          'EXECUTE'
        )
      )
  ) then
    raise exception
      'TEST_FAIL authenticated/service_role calendar RPC grant missing';
  end if;

  if has_table_privilege(
       'authenticated',
       'public.semesters',
       'INSERT'
     )
     or has_table_privilege(
       'authenticated',
       'public.semesters',
       'UPDATE'
     )
     or has_table_privilege(
       'authenticated',
       'public.semesters',
       'DELETE'
     )
     or has_table_privilege(
       'authenticated',
       'public.branch_semester_overrides',
       'INSERT'
     )
     or has_table_privilege(
       'authenticated',
       'public.branch_semester_overrides',
       'UPDATE'
     )
     or has_table_privilege(
       'authenticated',
       'public.branch_semester_overrides',
       'DELETE'
     )
     or has_table_privilege(
       'authenticated',
       'public.closure_periods',
       'INSERT'
     )
     or has_table_privilege(
       'authenticated',
       'public.closure_periods',
       'UPDATE'
     )
     or has_table_privilege(
       'authenticated',
       'public.closure_periods',
       'DELETE'
     )
  then
    raise exception
      'TEST_FAIL authenticated direct calendar table write is open';
  end if;

  -- ==========================================================
  -- FIXTURE CALENDAR
  -- ==========================================================

  select max(s.ends_on)
  into v_base_end
  from public.semesters s;

  if v_base_end is null then
    v_base_end := date '2030-01-06';
  end if;

  v_s1_start := v_base_end + 1;
  v_s1_original_end := v_s1_start + 34;
  v_s2_original_start := v_s1_original_end + 1;
  v_s2_end := v_s2_original_start + 27;

  v_s1_final_end := v_s1_start + 27;
  v_s2_final_start := v_s1_final_end + 1;

  insert into public.branches (
    id,
    name,
    is_active
  )
  values
    (
      v_branch_id,
      'ROLLBACK calendar '
        || left(v_branch_id::text, 8),
      true
    ),
    (
      v_other_branch_id,
      'ROLLBACK other '
        || left(v_other_branch_id::text, 8),
      true
    );

  insert into auth.users (id)
  values
    (v_master_id),
    (v_manager_id),
    (v_student_id);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values
    (
      v_master_id,
      'Rollback Calendar Master',
      'master'::public.user_role,
      null,
      true
    ),
    (
      v_manager_id,
      'Rollback Calendar Manager',
      'manager'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_id,
      'Rollback Calendar Student',
      'student'::public.user_role,
      v_branch_id,
      true
    );

  insert into public.teachers (
    id,
    withdrawal_date
  )
  values (
    v_manager_id,
    null
  );

  insert into public.students (
    id,
    status,
    withdrawal_date,
    student_type
  )
  values (
    v_student_id,
    'active'::public.student_status,
    null,
    'regular'::public.student_type
  );

  insert into public.semesters (
    id,
    code,
    starts_on,
    ends_on
  )
  values
    (
      v_semester1_id,
      'ROLLBACK-S1-'
        || left(v_semester1_id::text, 8),
      v_s1_start,
      v_s1_original_end
    ),
    (
      v_semester2_id,
      'ROLLBACK-S2-'
        || left(v_semester2_id::text, 8),
      v_s2_original_start,
      v_s2_end
    );

  if not private.global_semester_calendar_is_contiguous() then
    raise exception
      'TEST_FAIL fixture calendar not contiguous before batch';
  end if;

  -- ==========================================================
  -- MASTER GLOBAL BATCH
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
    true
  );

  v_result :=
    public.apply_semester_calendar_batch(
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'code',
            'ROLLBACK-S1-'
              || left(v_semester1_id::text, 8),
          'startsOn',
            v_s1_start,
          'endsOn',
            v_s1_final_end
        ),
        jsonb_build_object(
          'semesterId',
            v_semester2_id,
          'code',
            'ROLLBACK-S2-'
              || left(v_semester2_id::text, 8),
          'startsOn',
            v_s2_final_start,
          'endsOn',
            v_s2_end
        )
      )
    );

  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) <> true
     or (
       v_result ->> 'changedCount'
     )::integer <> 2
  then
    raise exception
      'TEST_FAIL master semester batch result unexpected: %',
      v_result;
  end if;

  if not private.global_semester_calendar_is_contiguous() then
    raise exception
      'TEST_FAIL global calendar not contiguous after master batch';
  end if;

  -- ==========================================================
  -- MANAGER GLOBAL BATCH FORBIDDEN
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  begin
    perform public.apply_semester_calendar_batch(
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'code',
            'ROLLBACK-S1-'
              || left(v_semester1_id::text, 8),
          'startsOn',
            v_s1_start,
          'endsOn',
            v_s1_final_end
        )
      )
    );

    raise exception
      'TEST_FAIL manager changed global semester calendar';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL manager changed global semester calendar'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_MASTER_REQUIRED'
      then
        raise exception
          'TEST_FAIL unexpected manager global-calendar error: %',
          v_message;
      end if;
  end;

  -- ==========================================================
  -- OWN BRANCH BATCH SUCCEEDS
  -- ==========================================================

  v_result :=
    public.apply_branch_semester_overrides_batch(
      v_branch_id,
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'startsOn',
            v_s1_start,
          'endsOn',
            v_s1_original_end
        ),
        jsonb_build_object(
          'semesterId',
            v_semester2_id,
          'startsOn',
            v_s2_original_start,
          'endsOn',
            v_s2_end
        )
      )
    );

  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) <> true
     or (
       v_result ->> 'changedCount'
     )::integer <> 2
  then
    raise exception
      'TEST_FAIL manager branch batch result unexpected: %',
      v_result;
  end if;

  if not private.branch_semester_calendar_is_contiguous(
    v_branch_id
  ) then
    raise exception
      'TEST_FAIL branch calendar not contiguous after manager batch';
  end if;

  -- ==========================================================
  -- WRONG BRANCH FORBIDDEN
  -- ==========================================================

  begin
    perform public.apply_branch_semester_overrides_batch(
      v_other_branch_id,
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'startsOn',
            v_s1_start,
          'endsOn',
            v_s1_original_end
        )
      )
    );

    raise exception
      'TEST_FAIL manager changed another branch calendar';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL manager changed another branch calendar'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN'
      then
        raise exception
          'TEST_FAIL unexpected wrong-branch error: %',
          v_message;
      end if;
  end;

  -- ==========================================================
  -- NON-CONTIGUOUS CHANGE ROLLS BACK
  -- ==========================================================

  begin
    perform public.apply_branch_semester_overrides_batch(
      v_branch_id,
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'startsOn',
            v_s1_start,
          'endsOn',
            v_s1_start + 41
        )
      )
    );

    raise exception
      'TEST_FAIL non-contiguous branch calendar accepted';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL non-contiguous branch calendar accepted'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_BRANCH_SEMESTER_CALENDAR_NOT_CONTIGUOUS'
      then
        raise exception
          'TEST_FAIL unexpected non-contiguous error: %',
          v_message;
      end if;
  end;

  if not private.branch_semester_calendar_is_contiguous(
    v_branch_id
  ) then
    raise exception
      'TEST_FAIL failed batch did not rollback branch calendar';
  end if;

  -- ==========================================================
  -- MATERIALIZATION LOCK
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
    v_semester1_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  );

  begin
    perform public.apply_branch_semester_overrides_batch(
      v_branch_id,
      jsonb_build_array(
        jsonb_build_object(
          'semesterId',
            v_semester1_id,
          'delete',
            true
        )
      )
    );

    raise exception
      'TEST_FAIL materialized branch semester override changed';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL materialized branch semester override changed'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_MATERIALIZED_BRANCH_SEMESTER_IMMUTABLE'
      then
        raise exception
          'TEST_FAIL unexpected materialization-lock error: %',
          v_message;
      end if;
  end;

  -- ==========================================================
  -- ORDINARY CLOSURE REMAINS OPERATIONAL
  -- ==========================================================

  v_result :=
    public.upsert_closure_period(
      null,
      v_branch_id,
      null,
      v_s1_start + 5,
      v_s1_start + 5,
      'ordinary'::public.closure_kind,
      'rollback ordinary closure'
    );

  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) <> true
  then
    raise exception
      'TEST_FAIL ordinary closure rejected after materialization: %',
      v_result;
  end if;

  -- ==========================================================
  -- INSTRUCTIONAL BREAK IS STRUCTURAL
  -- ==========================================================

  begin
    perform public.upsert_closure_period(
      null,
      v_branch_id,
      v_semester1_id,
      v_s1_start + 14,
      v_s1_start + 20,
      'instructional_break'::public.closure_kind,
      'rollback instructional break'
    );

    raise exception
      'TEST_FAIL materialized instructional break changed';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL materialized instructional break changed'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE'
      then
        raise exception
          'TEST_FAIL unexpected instructional-break lock error: %',
          v_message;
      end if;
  end;
end;
$test$;

rollback;
