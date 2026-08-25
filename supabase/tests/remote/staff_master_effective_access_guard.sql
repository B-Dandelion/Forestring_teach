begin;

do $test$
declare
  v_branch_id uuid := gen_random_uuid();
  v_manager_id uuid := gen_random_uuid();
  v_master_id uuid := gen_random_uuid();
  v_missing_staff_id uuid := gen_random_uuid();

  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_message text;
begin
  insert into public.branches (
    id,
    name
  )
  values (
    v_branch_id,
    'ROLLBACK staff master effective guard '
      || left(v_branch_id::text, 8)
  );

  insert into auth.users (id)
  values
    (v_manager_id),
    (v_master_id);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values
    (
      v_manager_id,
      'Rollback Departed Manager',
      'manager'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_master_id,
      'Rollback Inactive Master',
      'master'::public.user_role,
      null,
      false
    );

  insert into public.teachers (
    id,
    withdrawal_date
  )
  values (
    v_manager_id,
    v_today
  );

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
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
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );

  begin
    perform public.cancel_staff_departure(
      v_missing_staff_id
    );

    raise exception
      'TEST_FAIL cancel_staff_departure allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL cancel_staff_departure unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.schedule_staff_departure(
      v_missing_staff_id,
      v_today + 1
    );

    raise exception
      'TEST_FAIL schedule_staff_departure allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL schedule_staff_departure unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.finalize_staff_departure(
      v_missing_staff_id
    );

    raise exception
      'TEST_FAIL finalize_staff_departure allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL finalize_staff_departure unexpected error: %',
          v_message;
      end if;
  end;

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
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
      'sub', v_master_id::text,
      'role', 'authenticated'
    )::text,
    true
  );

  begin
    perform public.change_staff_role(
      v_missing_staff_id,
      'teacher'::public.user_role
    );

    raise exception
      'TEST_FAIL change_staff_role allowed ineffective master';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL change_staff_role unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.create_branch(
      'ROLLBACK should not be created'
    );

    raise exception
      'TEST_FAIL create_branch allowed ineffective master';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL create_branch unexpected error: %',
          v_message;
      end if;
  end;
end;
$test$;

rollback;
