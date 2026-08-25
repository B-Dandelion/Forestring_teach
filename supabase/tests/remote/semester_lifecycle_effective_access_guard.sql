begin;

do $test$
declare
  v_actor_id uuid := gen_random_uuid();
  v_branch_id uuid := gen_random_uuid();

  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_missing_plan_id uuid := gen_random_uuid();
  v_missing_plan_id_2 uuid := gen_random_uuid();

  v_message text;
begin
  insert into public.branches (
    id,
    name
  )
  values (
    v_branch_id,
    'ROLLBACK semester lifecycle effective guard '
      || left(v_branch_id::text, 8)
  );

  insert into auth.users (id)
  values (v_actor_id);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values (
    v_actor_id,
    'Rollback Departed Manager',
    'manager'::public.user_role,
    v_branch_id,
    true
  );

  insert into public.teachers (
    id,
    withdrawal_date
  )
  values (
    v_actor_id,
    v_today
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

  perform pg_catalog.set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_actor_id::text,
      'role', 'authenticated'
    )::text,
    true
  );

  begin
    perform public.activate_student_semester_plan(
      v_missing_plan_id
    );

    raise exception
      'TEST_FAIL activate_student_semester_plan allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL activate_student_semester_plan unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.finalize_student_semester_rights(
      v_missing_plan_id,
      v_missing_plan_id_2
    );

    raise exception
      'TEST_FAIL finalize_student_semester_rights allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL finalize_student_semester_rights unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.materialize_flex_base_rights(
      v_missing_plan_id
    );

    raise exception
      'TEST_FAIL materialize_flex_base_rights allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL materialize_flex_base_rights unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.transition_student_semester(
      v_missing_plan_id,
      v_missing_plan_id_2
    );

    raise exception
      'TEST_FAIL transition_student_semester allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL transition_student_semester unexpected error: %',
          v_message;
      end if;
  end;
end;
$test$;

rollback;
