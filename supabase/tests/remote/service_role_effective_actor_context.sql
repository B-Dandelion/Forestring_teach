begin;

do $test$
declare
  v_branch_id uuid := gen_random_uuid();
  v_manager_id uuid := gen_random_uuid();
  v_master_id uuid := gen_random_uuid();

  v_today date :=
    (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_message text;
  v_context jsonb;
begin
  insert into public.branches (
    id,
    name,
    is_active
  )
  values (
    v_branch_id,
    'ROLLBACK edge preflight '
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
      'Rollback Active Master',
      'master'::public.user_role,
      null,
      true
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
    perform public.admin_get_effective_actor_context(
      v_manager_id
    );

    raise exception
      'TEST_FAIL ineffective manager passed edge preflight';

  exception
    when insufficient_privilege then
      get stacked diagnostics
        v_message = message_text;

      if v_message <>
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        raise exception
          'TEST_FAIL unexpected edge preflight error: %',
          v_message;
      end if;
  end;

  v_context :=
    public.admin_get_effective_actor_context(
      v_master_id
    );

  if v_context ->> 'role' <> 'master' then
    raise exception
      'TEST_FAIL active master context role mismatch: %',
      v_context;
  end if;
end;
$test$;

rollback;
