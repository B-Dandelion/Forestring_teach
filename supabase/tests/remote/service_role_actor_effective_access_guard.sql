begin;

do $test$
declare
  v_branch_id uuid := gen_random_uuid();
  v_manager_id uuid := gen_random_uuid();
  v_master_id uuid := gen_random_uuid();
  v_target_id uuid := gen_random_uuid();

  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_message text;
  v_rate_key text := repeat('a', 64);
begin
  insert into public.branches (
    id,
    name,
    is_active
  )
  values (
    v_branch_id,
    'ROLLBACK service role effective guard '
      || left(v_branch_id::text, 8),
    true
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

  begin
    perform public.admin_create_student_account_data(
      v_manager_id,
      v_target_id,
      'Should Not Create',
      'Should Not Create',
      'dummy-hash',
      repeat('b', 64),
      v_branch_id,
      'regular'::public.student_type
    );

    raise exception
      'TEST_FAIL admin_create_student_account_data allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_create_student_account_data unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.admin_get_account_pin_reset_context(
      v_manager_id,
      v_target_id
    );

    raise exception
      'TEST_FAIL admin_get_account_pin_reset_context allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_get_account_pin_reset_context unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.admin_reset_account_pin_and_unlock_data(
      v_manager_id,
      v_target_id,
      'dummy-hash',
      repeat('c', 64),
      'dummy-name',
      v_rate_key
    );

    raise exception
      'TEST_FAIL admin_reset_account_pin_and_unlock_data allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_reset_account_pin_and_unlock_data unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.admin_update_account_name_data(
      v_manager_id,
      v_target_id,
      'Should Not Rename',
      'Should Not Rename'
    );

    raise exception
      'TEST_FAIL admin_update_account_name_data allowed ineffective manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_update_account_name_data unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.admin_create_manager_account_data(
      v_master_id,
      v_target_id,
      'Should Not Create Manager',
      'Should Not Create Manager',
      'dummy-hash',
      repeat('d', 64),
      v_branch_id,
      '[]'::jsonb
    );

    raise exception
      'TEST_FAIL admin_create_manager_account_data allowed ineffective master';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_create_manager_account_data unexpected error: %',
          v_message;
      end if;
  end;

  begin
    perform public.admin_create_teacher_account_data(
      v_master_id,
      v_target_id,
      'Should Not Create Teacher',
      'Should Not Create Teacher',
      'dummy-hash',
      repeat('e', 64),
      v_branch_id,
      '[]'::jsonb
    );

    raise exception
      'TEST_FAIL admin_create_teacher_account_data allowed ineffective master';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL admin_create_teacher_account_data unexpected error: %',
          v_message;
      end if;
  end;
end;
$test$;

rollback;
