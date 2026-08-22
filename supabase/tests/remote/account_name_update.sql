begin;

do $$
declare
  v_master_id uuid;

  v_manager_id uuid;
  v_manager_branch_id uuid;
  v_manager_original_name text;
  v_manager_original_login text;
  v_manager_original_hash text;
  v_manager_original_fingerprint text;

  v_target_id uuid;
  v_target_role public.user_role;
  v_target_branch_id uuid;
  v_target_original_active boolean;
  v_target_original_name text;
  v_target_original_login text;
  v_target_original_hash text;
  v_target_original_fingerprint text;

  v_collision_id uuid;
  v_collision_name text;
  v_collision_hash text;
  v_collision_fingerprint text;

  v_test_name text;
  v_manager_test_name text;
  v_inactive_test_name text;
  v_collision_source_name text;
  v_forbidden_name text;

  v_current_text text;
  v_current_bool boolean;
  v_current_role public.user_role;
  v_current_branch uuid;

  v_before_audit integer;
  v_after_audit integer;

  v_result jsonb;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. FIXTURES
  -- ==========================================================

  select p.id
  into v_master_id
  from public.profiles p
  where p.role = 'master'::public.user_role
    and p.is_active = true
  order by p.created_at
  limit 1;

  if v_master_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master';
  end if;


  -- Active manager with a valid login credential.
  select
    p.id,
    p.branch_id,
    p.display_name,
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_manager_id,
    v_manager_branch_id,
    v_manager_original_name,
    v_manager_original_login,
    v_manager_original_hash,
    v_manager_original_fingerprint
  from public.profiles p
  join private.login_credentials c
    on c.profile_id = p.id
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
    and p.display_name = c.login_name_normalized
  order by p.created_at
  limit 1;

  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active manager with credential';
  end if;


  -- Same-branch teacher/student controlled by that manager.
  select
    p.id,
    p.role,
    p.branch_id,
    p.is_active,
    p.display_name,
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_target_id,
    v_target_role,
    v_target_branch_id,
    v_target_original_active,
    v_target_original_name,
    v_target_original_login,
    v_target_original_hash,
    v_target_original_fingerprint
  from public.profiles p
  join private.login_credentials c
    on c.profile_id = p.id
  where p.id <> v_manager_id
    and p.branch_id = v_manager_branch_id
    and p.role in (
      'teacher'::public.user_role,
      'student'::public.user_role
    )
    and p.is_active = true
    and p.display_name = c.login_name_normalized
  order by
    case
      when p.role = 'student'::public.user_role then 0
      else 1
    end,
    p.created_at
  limit 1;

  if v_target_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: same-branch active teacher/student with credential';
  end if;


  v_test_name :=
    '__FORESTRING_NAME_TEST_' ||
    substr(md5(clock_timestamp()::text || random()::text), 1, 16);

  v_manager_test_name :=
    '__FORESTRING_MANAGER_TEST_' ||
    substr(md5(clock_timestamp()::text || random()::text), 1, 16);

  v_inactive_test_name :=
    '__FORESTRING_INACTIVE_TEST_' ||
    substr(md5(clock_timestamp()::text || random()::text), 1, 16);

  v_collision_source_name :=
    '__FORESTRING_COLLISION_TEST_' ||
    substr(md5(clock_timestamp()::text || random()::text), 1, 16);

  v_forbidden_name :=
    '__FORESTRING_FORBIDDEN_TEST_' ||
    substr(md5(clock_timestamp()::text || random()::text), 1, 16);


  -- ==========================================================
  -- 2. MASTER CAN RENAME TARGET
  -- ==========================================================

  select count(*)::integer
  into v_before_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_NAME_CHANGED';


  v_result :=
    public.admin_update_account_name_data(
      v_master_id,
      v_target_id,
      v_test_name,
      v_test_name
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then
    raise exception
      'TEST_FAILED: master rename returned changed=false';
  end if;


  select
    p.display_name,
    p.role,
    p.branch_id,
    p.is_active
  into
    v_current_text,
    v_current_role,
    v_current_branch,
    v_current_bool
  from public.profiles p
  where p.id = v_target_id;


  if v_current_text <> v_test_name then
    raise exception
      'TEST_FAILED: profile display name was not changed';
  end if;

  if v_current_role <> v_target_role then
    raise exception
      'TEST_FAILED: target role changed during rename';
  end if;

  if v_current_branch is distinct from v_target_branch_id then
    raise exception
      'TEST_FAILED: target branch changed during rename';
  end if;

  if v_current_bool is distinct from v_target_original_active then
    raise exception
      'TEST_FAILED: target active state changed during rename';
  end if;


  select c.login_name_normalized
  into v_current_text
  from private.login_credentials c
  where c.profile_id = v_target_id;

  if v_current_text <> v_test_name then
    raise exception
      'TEST_FAILED: login name was not changed with display name';
  end if;


  -- PIN material MUST remain byte-for-byte unchanged.
  if exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and (
        c.pin_hash is distinct from v_target_original_hash
        or
        c.pin_fingerprint is distinct from
          v_target_original_fingerprint
      )
  ) then
    raise exception
      'TEST_FAILED: PIN credential changed during name update';
  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_NAME_CHANGED';

  if v_after_audit <> v_before_audit + 1 then
    raise exception
      'TEST_FAILED: successful rename audit missing';
  end if;


  -- ==========================================================
  -- 3. SAME NAME IS IDEMPOTENT
  -- ==========================================================

  v_before_audit := v_after_audit;


  v_result :=
    public.admin_update_account_name_data(
      v_master_id,
      v_target_id,
      v_test_name,
      v_test_name
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then
    raise exception
      'TEST_FAILED: same-name update was not idempotent';
  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_NAME_CHANGED';

  if v_after_audit <> v_before_audit then
    raise exception
      'TEST_FAILED: idempotent rename created audit';
  end if;


  -- ==========================================================
  -- 4. DB REFUSES DISPLAY/LOGIN NAME DIVERGENCE
  -- ==========================================================

  v_denied := false;

  begin
    perform public.admin_update_account_name_data(
      v_master_id,
      v_target_id,
      v_test_name,
      v_test_name || '_DIFFERENT'
    );

  exception
    when others then
      if sqlerrm = 'FORESTRING_ACCOUNT_NAME_MISMATCH' then
        v_denied := true;
      else
        raise;
      end if;
  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: divergent display/login name accepted';
  end if;


  -- State must still be the successful test name.
  if not exists (
    select 1
    from public.profiles p
    join private.login_credentials c
      on c.profile_id = p.id
    where p.id = v_target_id
      and p.display_name = v_test_name
      and c.login_name_normalized = v_test_name
  ) then
    raise exception
      'TEST_FAILED: mismatch rejection mutated account';
  end if;


  -- Restore target before the next authorization tests.
  perform public.admin_update_account_name_data(
    v_master_id,
    v_target_id,
    v_target_original_name,
    v_target_original_login
  );


  -- ==========================================================
  -- 5. MANAGER MAY RENAME SELF
  -- ==========================================================

  v_result :=
    public.admin_update_account_name_data(
      v_manager_id,
      v_manager_id,
      v_manager_test_name,
      v_manager_test_name
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then
    raise exception
      'TEST_FAILED: manager could not rename self';
  end if;


  if not exists (
    select 1
    from public.profiles p
    join private.login_credentials c
      on c.profile_id = p.id
    where p.id = v_manager_id
      and p.display_name = v_manager_test_name
      and c.login_name_normalized = v_manager_test_name
      and c.pin_hash = v_manager_original_hash
      and c.pin_fingerprint =
          v_manager_original_fingerprint
  ) then
    raise exception
      'TEST_FAILED: manager self rename state incorrect';
  end if;


  perform public.admin_update_account_name_data(
    v_manager_id,
    v_manager_id,
    v_manager_original_name,
    v_manager_original_login
  );


  -- ==========================================================
  -- 6. MANAGER MAY RENAME OWN-BRANCH INACTIVE TEACHER/STUDENT
  --
  -- Test-only temporary inactive flag. Entire transaction rolls
  -- back at the end.
  -- ==========================================================

  update public.profiles
  set is_active = false
  where id = v_target_id;


  v_result :=
    public.admin_update_account_name_data(
      v_manager_id,
      v_target_id,
      v_inactive_test_name,
      v_inactive_test_name
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then
    raise exception
      'TEST_FAILED: manager could not rename inactive own-branch target';
  end if;


  if not exists (
    select 1
    from public.profiles p
    join private.login_credentials c
      on c.profile_id = p.id
    where p.id = v_target_id
      and p.is_active = false
      and p.display_name = v_inactive_test_name
      and c.login_name_normalized = v_inactive_test_name
      and c.pin_hash = v_target_original_hash
      and c.pin_fingerprint =
          v_target_original_fingerprint
  ) then
    raise exception
      'TEST_FAILED: inactive target rename state incorrect';
  end if;


  -- Rename back while still inactive.
  perform public.admin_update_account_name_data(
    v_manager_id,
    v_target_id,
    v_target_original_name,
    v_target_original_login
  );


  update public.profiles
  set is_active = v_target_original_active
  where id = v_target_id;


  -- ==========================================================
  -- 7. TEACHER/STUDENT MAY NOT RENAME EVEN SELF
  -- ==========================================================

  v_denied := false;

  begin
    perform public.admin_update_account_name_data(
      v_target_id,
      v_target_id,
      v_forbidden_name,
      v_forbidden_name
    );

  exception
    when others then
      if sqlerrm =
         'FORESTRING_ACCOUNT_NAME_UPDATE_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;
  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher/student renamed own account';
  end if;


  -- ==========================================================
  -- 8. MANAGER MAY NOT RENAME MASTER
  -- ==========================================================

  v_denied := false;

  begin
    perform public.admin_update_account_name_data(
      v_manager_id,
      v_master_id,
      v_forbidden_name,
      v_forbidden_name
    );

  exception
    when others then
      if sqlerrm =
         'FORESTRING_ACCOUNT_NAME_UPDATE_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;
  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: manager renamed master';
  end if;


  -- ==========================================================
  -- 9. SAME NAME + SAME PIN COLLISION MUST ROLLBACK ATOMICALLY
  --
  -- We deliberately give the target another account's PIN
  -- fingerprint inside this rollback-only test, while keeping a
  -- unique temporary name. Then renaming to that account's name
  -- must hit the unique constraint.
  -- ==========================================================

  perform public.admin_update_account_name_data(
    v_master_id,
    v_target_id,
    v_collision_source_name,
    v_collision_source_name
  );


  select
    p.id,
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_collision_id,
    v_collision_name,
    v_collision_hash,
    v_collision_fingerprint
  from public.profiles p
  join private.login_credentials c
    on c.profile_id = p.id
  where p.id <> v_target_id
    and c.login_name_normalized <>
        v_collision_source_name
  order by p.created_at
  limit 1;


  if v_collision_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second login credential for collision test';
  end if;


  -- Safe because target currently has a globally unique test name.
  update private.login_credentials
  set
    pin_hash = v_collision_hash,
    pin_fingerprint = v_collision_fingerprint
  where profile_id = v_target_id;


  select count(*)::integer
  into v_before_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_NAME_CHANGED';


  v_denied := false;

  begin
    perform public.admin_update_account_name_data(
      v_master_id,
      v_target_id,
      v_collision_name,
      v_collision_name
    );

  exception
    when others then
      if sqlerrm =
         'FORESTRING_NAME_PIN_ALREADY_IN_USE' then
        v_denied := true;
      else
        raise;
      end if;
  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: duplicate name+PIN combination accepted';
  end if;


  -- BOTH names must remain untouched after failed transaction.
  if not exists (
    select 1
    from public.profiles p
    join private.login_credentials c
      on c.profile_id = p.id
    where p.id = v_target_id
      and p.display_name = v_collision_source_name
      and c.login_name_normalized =
          v_collision_source_name
      and c.pin_hash = v_collision_hash
      and c.pin_fingerprint =
          v_collision_fingerprint
  ) then
    raise exception
      'TEST_FAILED: duplicate collision left partial name update';
  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_NAME_CHANGED';


  if v_after_audit <> v_before_audit then
    raise exception
      'TEST_FAILED: failed collision created audit';
  end if;

end;
$$;


select
  'PASS: account name update / display+login atomic / PIN preserved / manager scope / inactive target / idempotency / duplicate rollback / audit'
  as test_result;

rollback;
