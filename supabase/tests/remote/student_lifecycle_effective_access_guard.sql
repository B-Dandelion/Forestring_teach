begin;

do $test$
declare
  v_actor_id uuid := gen_random_uuid();
  v_branch_id uuid := gen_random_uuid();
  v_target_student_id uuid := gen_random_uuid();

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
    'ROLLBACK student lifecycle effective guard '
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

  -- cancel_student_withdrawal
  begin
    perform public.cancel_student_withdrawal(
      v_target_student_id
    );

    raise exception
      'TEST_FAIL cancel_student_withdrawal allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL cancel_student_withdrawal unexpected error: %',
          v_message;
      end if;
  end;

  -- finalize_student_withdrawal
  begin
    perform public.finalize_student_withdrawal(
      v_target_student_id
    );

    raise exception
      'TEST_FAIL finalize_student_withdrawal allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL finalize_student_withdrawal unexpected error: %',
          v_message;
      end if;
  end;

  -- reactivate_student
  begin
    perform public.reactivate_student(
      v_target_student_id
    );

    raise exception
      'TEST_FAIL reactivate_student allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL reactivate_student unexpected error: %',
          v_message;
      end if;
  end;

  -- schedule_student_withdrawal
  begin
    perform public.schedule_student_withdrawal(
      v_target_student_id,
      v_today + 7
    );

    raise exception
      'TEST_FAIL schedule_student_withdrawal allowed departed manager';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL schedule_student_withdrawal unexpected error: %',
          v_message;
      end if;
  end;
end;
$test$;

rollback;
