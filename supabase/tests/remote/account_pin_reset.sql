begin;

do $$
declare
  v_master_id uuid;

  v_manager_id uuid;
  v_manager_branch_id uuid;
  v_manager_hash text;
  v_manager_fingerprint text;

  v_target_id uuid;
  v_target_role public.user_role;
  v_target_branch_id uuid;
  v_target_active boolean;
  v_target_display_name text;
  v_target_login_name text;
  v_target_hash text;
  v_target_fingerprint text;

  v_collision_id uuid;
  v_collision_login_name text;
  v_collision_hash text;
  v_collision_fingerprint text;

  v_test_hash text;
  v_same_pin_fake_hash text;
  v_test_fingerprint text;

  v_current_login text;
  v_current_hash text;
  v_current_fingerprint text;

  v_before_audit integer;
  v_after_audit integer;

  v_result jsonb;
  v_denied boolean;

  v_subject_a text;
  v_subject_b text;

  v_name_bucket text;
  v_pair_bucket text;
  v_ip_bucket text;
  v_other_bucket text;
  v_legacy_bucket text;

  v_deleted integer;
  v_count integer;
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


  select
    p.id,
    p.branch_id,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_manager_id,
    v_manager_branch_id,
    v_manager_hash,
    v_manager_fingerprint
  from public.profiles p
  join private.login_credentials c
    on c.profile_id = p.id
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
  order by p.created_at
  limit 1;

  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active manager with credential';
  end if;


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
    v_target_active,
    v_target_display_name,
    v_target_login_name,
    v_target_hash,
    v_target_fingerprint
  from public.profiles p
  join private.login_credentials c
    on c.profile_id = p.id
  where p.branch_id = v_manager_branch_id
    and p.role in (
      'teacher'::public.user_role,
      'student'::public.user_role
    )
    and p.is_active = true
    and p.display_name = c.login_name_normalized
    and p.id <> v_manager_id
  order by
    case
      when p.role = 'student'::public.user_role
        then 0
      else 1
    end,
    p.created_at
  limit 1;

  if v_target_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: same-branch active teacher/student';
  end if;


  -- Find another credential usable for a deterministic
  -- name+PIN collision test.
  select
    c.profile_id,
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_collision_id,
    v_collision_login_name,
    v_collision_hash,
    v_collision_fingerprint
  from private.login_credentials c
  where c.profile_id <> v_target_id
    and c.login_name_normalized <> v_target_login_name
    and c.pin_fingerprint <> v_target_fingerprint

    -- Temporarily moving target to this login name must itself
    -- remain unique with the target's original fingerprint.
    and not exists (
      select 1
      from private.login_credentials x
      where x.login_name_normalized =
            c.login_name_normalized
        and x.pin_fingerprint =
            v_target_fingerprint
    )
  order by c.created_at
  limit 1;

  if v_collision_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second credential for collision test';
  end if;


  -- ==========================================================
  -- 2. SYNTHETIC PIN MATERIAL
  --
  -- PostgreSQL never sees raw PIN.
  -- Test hash is intentionally just a marker because DB only
  -- stores trusted Edge output.
  -- ==========================================================

  v_test_fingerprint :=
    md5(
      clock_timestamp()::text
      || random()::text
    )
    ||
    md5(
      random()::text
      || clock_timestamp()::text
    );

  -- Extremely defensive collision avoidance.
  while exists (
    select 1
    from private.login_credentials c
    where c.login_name_normalized =
          v_target_login_name
      and c.pin_fingerprint =
          v_test_fingerprint
  )
  loop
    v_test_fingerprint :=
      md5(
        clock_timestamp()::text
        || random()::text
      )
      ||
      md5(
        random()::text
        || clock_timestamp()::text
      );
  end loop;


  v_test_hash :=
    '__FORESTRING_TEST_PIN_HASH_' ||
    md5(
      clock_timestamp()::text
      || random()::text
    );

  v_same_pin_fake_hash :=
    '__FORESTRING_SHOULD_NOT_REPLACE_HASH_' ||
    md5(
      random()::text
    );


  -- ==========================================================
  -- 3. MASTER PIN RESET
  -- ==========================================================

  select count(*)::integer
  into v_before_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_PIN_RESET';


  v_result :=
    public.admin_reset_account_pin_data(
      v_master_id,
      v_target_id,
      v_test_hash,
      v_test_fingerprint
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: master PIN reset returned changed=false';

  end if;


  select
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_current_login,
    v_current_hash,
    v_current_fingerprint
  from private.login_credentials c
  where c.profile_id = v_target_id;


  if v_current_login <> v_target_login_name then
    raise exception
      'TEST_FAILED: PIN reset changed login name';
  end if;


  if v_current_hash <> v_test_hash
     or v_current_fingerprint <>
        v_test_fingerprint then

    raise exception
      'TEST_FAILED: new PIN material not stored';

  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_target_id
      and p.display_name =
          v_target_display_name
      and p.role =
          v_target_role
      and p.branch_id is not distinct from
          v_target_branch_id
      and p.is_active is not distinct from
          v_target_active
  ) then

    raise exception
      'TEST_FAILED: PIN reset mutated profile state';

  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_PIN_RESET';


  if v_after_audit <> v_before_audit + 1 then
    raise exception
      'TEST_FAILED: PIN reset audit missing';
  end if;


  -- Audit must NEVER contain hash/fingerprint.
  if exists (
    select 1
    from public.audit_events a
    where a.subject_profile_id = v_target_id
      and a.event_type = 'ACCOUNT_PIN_RESET'
      and (
        a.details::text like
          '%' || v_test_hash || '%'
        or
        a.details::text like
          '%' || v_test_fingerprint || '%'
      )
  ) then

    raise exception
      'TEST_FAILED: PIN material leaked into audit';

  end if;


  -- ==========================================================
  -- 4. SAME PIN FINGERPRINT
  --
  -- bcrypt would normally create another salted hash even for
  -- the same raw PIN. DB intentionally does NOT replace it when
  -- fingerprint says the actual PIN did not change.
  --
  -- Audit still occurs because this is a privileged reset
  -- operation and may be used to clear login locks.
  -- ==========================================================

  v_before_audit :=
    v_after_audit;


  v_result :=
    public.admin_reset_account_pin_data(
      v_master_id,
      v_target_id,
      v_same_pin_fake_hash,
      v_test_fingerprint
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: same PIN fingerprint returned changed=true';

  end if;


  select c.pin_hash
  into v_current_hash
  from private.login_credentials c
  where c.profile_id = v_target_id;


  if v_current_hash <> v_test_hash then
    raise exception
      'TEST_FAILED: same PIN unnecessarily replaced bcrypt hash';
  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_PIN_RESET';


  if v_after_audit <> v_before_audit + 1 then
    raise exception
      'TEST_FAILED: same PIN reset was not audited';
  end if;


  if exists (
    select 1
    from public.audit_events a
    where a.subject_profile_id = v_target_id
      and a.event_type = 'ACCOUNT_PIN_RESET'
      and a.details::text like
          '%' || v_same_pin_fake_hash || '%'
  ) then

    raise exception
      'TEST_FAILED: same-PIN hash marker leaked into audit';

  end if;


  -- ==========================================================
  -- 5. MANAGER MAY RESET OWN-BRANCH TEACHER/STUDENT
  --
  -- Restore target's original credential through the real RPC.
  -- ==========================================================

  v_result :=
    public.admin_reset_account_pin_data(
      v_manager_id,
      v_target_id,
      v_target_hash,
      v_target_fingerprint
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: manager could not reset own-branch target';

  end if;


  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and c.login_name_normalized =
          v_target_login_name
      and c.pin_hash =
          v_target_hash
      and c.pin_fingerprint =
          v_target_fingerprint
  ) then

    raise exception
      'TEST_FAILED: manager target PIN reset state incorrect';

  end if;


  -- ==========================================================
  -- 6. MANAGER MAY RESET SELF
  --
  -- Same fingerprint => no credential mutation.
  -- ==========================================================

  v_result :=
    public.admin_reset_account_pin_data(
      v_manager_id,
      v_manager_id,
      '__FORESTRING_MANAGER_HASH_SHOULD_NOT_REPLACE',
      v_manager_fingerprint
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: manager self reset failed';

  end if;


  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_manager_id
      and c.pin_hash = v_manager_hash
      and c.pin_fingerprint =
          v_manager_fingerprint
  ) then

    raise exception
      'TEST_FAILED: manager self reset mutated same PIN hash';

  end if;


  -- ==========================================================
  -- 7. TEACHER/STUDENT CANNOT RESET PIN
  -- ==========================================================

  v_denied := false;

  begin

    perform public.admin_reset_account_pin_data(
      v_target_id,
      v_target_id,
      '__FORESTRING_FORBIDDEN_HASH',
      v_target_fingerprint
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_PIN_RESET_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher/student reset own PIN';
  end if;


  -- ==========================================================
  -- 8. MANAGER CANNOT RESET MASTER
  -- ==========================================================

  v_denied := false;

  begin

    perform public.admin_reset_account_pin_data(
      v_manager_id,
      v_master_id,
      '__FORESTRING_FORBIDDEN_MASTER_HASH',
      v_test_fingerprint
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_PIN_RESET_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: manager reset master PIN';
  end if;


  -- ==========================================================
  -- 9. INACTIVE OWN-BRANCH TARGET MAY STILL BE RESET
  --
  -- Useful before/around account reactivation.
  -- Entire change rolls back at end of test.
  -- ==========================================================

  update public.profiles
  set is_active = false
  where id = v_target_id;


  v_result :=
    public.admin_reset_account_pin_data(
      v_manager_id,
      v_target_id,
      '__FORESTRING_INACTIVE_SAME_PIN_HASH',
      v_target_fingerprint
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: inactive own-branch target reset rejected';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_target_id
      and p.is_active = false
  ) then

    raise exception
      'TEST_FAILED: inactive target unexpectedly reactivated';
  end if;


  update public.profiles
  set is_active = v_target_active
  where id = v_target_id;


  -- ==========================================================
  -- 10. SAME NAME + SAME PIN COLLISION
  --
  -- Temporarily give target another account's LOGIN NAME while
  -- keeping target's original PIN. That state is legal because
  -- same names are allowed when fingerprints differ.
  --
  -- Resetting target to the other account's fingerprint must
  -- then hit the unique(name,fingerprint) constraint.
  -- ==========================================================

  update private.login_credentials
  set login_name_normalized =
      v_collision_login_name
  where profile_id =
        v_target_id;


  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and c.login_name_normalized =
          v_collision_login_name
      and c.pin_hash =
          v_target_hash
      and c.pin_fingerprint =
          v_target_fingerprint
  ) then

    raise exception
      'TEST_FAILED: collision fixture setup failed';

  end if;


  select count(*)::integer
  into v_before_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_PIN_RESET';


  v_denied := false;

  begin

    perform public.admin_reset_account_pin_data(
      v_master_id,
      v_target_id,
      v_collision_hash,
      v_collision_fingerprint
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
      'TEST_FAILED: duplicate name+PIN accepted';
  end if;


  -- Failed PIN reset must leave credential completely unchanged.
  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and c.login_name_normalized =
          v_collision_login_name
      and c.pin_hash =
          v_target_hash
      and c.pin_fingerprint =
          v_target_fingerprint
  ) then

    raise exception
      'TEST_FAILED: duplicate collision left partial credential update';

  end if;


  select count(*)::integer
  into v_after_audit
  from public.audit_events a
  where a.subject_profile_id = v_target_id
    and a.event_type = 'ACCOUNT_PIN_RESET';


  if v_after_audit <> v_before_audit then
    raise exception
      'TEST_FAILED: failed duplicate reset created audit';
  end if;


  -- Restore login name for remaining tests.
  update private.login_credentials
  set login_name_normalized =
      v_target_login_name
  where profile_id =
        v_target_id;


  -- ==========================================================
  -- 11. SUBJECT-SCOPED RATE LIMITS
  -- ==========================================================

  v_subject_a :=
    md5('subject-a-' || random()::text)
    ||
    md5('subject-a-2-' || random()::text);

  v_subject_b :=
    md5('subject-b-' || random()::text)
    ||
    md5('subject-b-2-' || random()::text);


  v_name_bucket :=
    md5('name-' || random()::text)
    ||
    md5('name-2-' || random()::text);

  v_pair_bucket :=
    md5('pair-' || random()::text)
    ||
    md5('pair-2-' || random()::text);

  v_ip_bucket :=
    md5('ip-' || random()::text)
    ||
    md5('ip-2-' || random()::text);

  v_other_bucket :=
    md5('other-' || random()::text)
    ||
    md5('other-2-' || random()::text);

  v_legacy_bucket :=
    md5('legacy-' || random()::text)
    ||
    md5('legacy-2-' || random()::text);


  -- Name bucket -> subject A
  perform public.auth_record_login_failure_scoped(
    v_name_bucket,
    v_subject_a,
    900,
    10,
    900
  );


  -- Pair bucket -> subject A
  perform public.auth_record_login_failure_scoped(
    v_pair_bucket,
    v_subject_a,
    600,
    5,
    900
  );


  -- IP bucket -> NO subject
  perform public.auth_record_login_failure_scoped(
    v_ip_bucket,
    null,
    900,
    30,
    1800
  );


  -- Another user -> subject B
  perform public.auth_record_login_failure_scoped(
    v_other_bucket,
    v_subject_b,
    900,
    10,
    900
  );


  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_name_bucket
      and r.subject_key = v_subject_a
      and r.failed_attempts = 1
  ) then

    raise exception
      'TEST_FAILED: scoped name rate limit not recorded';

  end if;


  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_ip_bucket
      and r.subject_key is null
      and r.failed_attempts = 1
  ) then

    raise exception
      'TEST_FAILED: IP bucket unexpectedly received subject';
  end if;


  -- ==========================================================
  -- 12. LEGACY NULL-SUBJECT ROW ADOPTION
  --
  -- Existing rows created by the old login Edge have NULL
  -- subject_key. First new scoped access must attach subject.
  -- ==========================================================

  insert into private.login_rate_limits (
    bucket_key,
    subject_key,
    failed_attempts,
    window_started_at,
    locked_until
  )
  values (
    v_legacy_bucket,
    null,
    0,
    pg_catalog.now(),
    null
  );


  perform public.auth_record_login_failure_scoped(
    v_legacy_bucket,
    v_subject_a,
    900,
    10,
    900
  );


  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_legacy_bucket
      and r.subject_key = v_subject_a
      and r.failed_attempts = 1
  ) then

    raise exception
      'TEST_FAILED: legacy rate-limit row did not adopt subject';
  end if;


  -- Once assigned, another subject must never hijack it.
  v_denied := false;

  begin

    perform public.auth_record_login_failure_scoped(
      v_legacy_bucket,
      v_subject_b,
      900,
      10,
      900
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_RATE_LIMIT_SCOPE_MISMATCH' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: rate-limit subject hijack accepted';
  end if;


  -- ==========================================================
  -- 13. CLEAR SUBJECT A
  --
  -- Must remove:
  --   name
  --   pair
  --   adopted legacy
  --
  -- Must preserve:
  --   IP bucket
  --   subject B bucket
  -- ==========================================================

  v_deleted :=
    public.auth_clear_login_rate_limits_for_subject(
      v_subject_a
    );


  if v_deleted <> 3 then
    raise exception
      'TEST_FAILED: subject clear deleted %, expected 3',
      v_deleted;
  end if;


  select count(*)::integer
  into v_count
  from private.login_rate_limits r
  where r.bucket_key in (
    v_name_bucket,
    v_pair_bucket,
    v_legacy_bucket
  );

  if v_count <> 0 then
    raise exception
      'TEST_FAILED: subject-A rate-limit rows remain';
  end if;


  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_ip_bucket
      and r.subject_key is null
  ) then

    raise exception
      'TEST_FAILED: subject clear deleted IP bucket';
  end if;


  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_other_bucket
      and r.subject_key = v_subject_b
  ) then

    raise exception
      'TEST_FAILED: subject clear deleted another subject';
  end if;


  -- ==========================================================
  -- 14. FINAL ACCOUNT INVARIANTS
  -- ==========================================================

  if not exists (
    select 1
    from public.profiles p
    join private.login_credentials c
      on c.profile_id = p.id
    where p.id = v_target_id
      and p.display_name =
          v_target_display_name
      and p.role =
          v_target_role
      and p.branch_id is not distinct from
          v_target_branch_id
      and p.is_active is not distinct from
          v_target_active
      and c.login_name_normalized =
          v_target_login_name
      and c.pin_hash =
          v_target_hash
      and c.pin_fingerprint =
          v_target_fingerprint
  ) then

    raise exception
      'TEST_FAILED: target account was not restored cleanly';
  end if;

end;
$$;


select
  'PASS: PIN reset / credential atomicity / same-PIN preservation / master+manager scope / inactive target / sensitive audit safety / duplicate rollback / subject-scoped rate limits'
  as test_result;

rollback;
