begin;

do $$
declare
  v_master_id uuid;

  v_target_id uuid;
  v_login_name text;

  v_original_hash text;
  v_original_fingerprint text;

  v_new_hash text;
  v_new_fingerprint text;

  v_subject_key text;

  v_name_bucket text;
  v_pair_bucket text;
  v_ip_bucket text;

  v_result jsonb;

  v_denied boolean;
begin

  -- ==========================================================
  -- FIXTURES
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
    c.profile_id,
    c.login_name_normalized,
    c.pin_hash,
    c.pin_fingerprint
  into
    v_target_id,
    v_login_name,
    v_original_hash,
    v_original_fingerprint
  from private.login_credentials c
  join public.profiles p
    on p.id = c.profile_id
  where p.id <> v_master_id
  order by p.created_at
  limit 1;


  if v_target_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: target credential';
  end if;


  -- Context must resolve the same login name.
  if public.admin_get_account_pin_reset_context(
       v_master_id,
       v_target_id
     ) <> v_login_name then

    raise exception
      'TEST_FAILED: PIN reset context returned wrong login name';

  end if;


  -- ==========================================================
  -- SYNTHETIC VALUES
  -- ==========================================================

  v_subject_key :=
    md5('subject-a-' || random()::text)
    ||
    md5('subject-b-' || random()::text);


  v_name_bucket :=
    md5('name-a-' || random()::text)
    ||
    md5('name-b-' || random()::text);


  v_pair_bucket :=
    md5('pair-a-' || random()::text)
    ||
    md5('pair-b-' || random()::text);


  v_ip_bucket :=
    md5('ip-a-' || random()::text)
    ||
    md5('ip-b-' || random()::text);


  v_new_fingerprint :=
    md5('fp-a-' || random()::text)
    ||
    md5('fp-b-' || random()::text);


  while exists (
    select 1
    from private.login_credentials c
    where c.login_name_normalized =
          v_login_name
      and c.pin_fingerprint =
          v_new_fingerprint
  )
  loop

    v_new_fingerprint :=
      md5('fp-c-' || random()::text)
      ||
      md5('fp-d-' || random()::text);

  end loop;


  v_new_hash :=
    '__FORESTRING_ATOMIC_TEST_HASH_' ||
    md5(random()::text);


  -- ==========================================================
  -- RATE LIMIT FIXTURES
  -- ==========================================================

  perform
    public.auth_record_login_failure_scoped(
      v_name_bucket,
      v_subject_key,
      900,
      10,
      900
    );


  perform
    public.auth_record_login_failure_scoped(
      v_pair_bucket,
      v_subject_key,
      600,
      5,
      900
    );


  perform
    public.auth_record_login_failure_scoped(
      v_ip_bucket,
      null,
      900,
      30,
      1800
    );


  -- ==========================================================
  -- RESET + UNLOCK
  -- ==========================================================

  v_result :=
    public.admin_reset_account_pin_and_unlock_data(
      v_master_id,
      v_target_id,
      v_new_hash,
      v_new_fingerprint,
      v_login_name,
      v_subject_key
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: atomic PIN reset did not change credential';

  end if;


  if (v_result ->> 'clearedRateLimitCount')::integer
     <> 2 then

    raise exception
      'TEST_FAILED: expected 2 subject rate limits cleared';

  end if;


  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and c.login_name_normalized =
          v_login_name
      and c.pin_hash =
          v_new_hash
      and c.pin_fingerprint =
          v_new_fingerprint
  ) then

    raise exception
      'TEST_FAILED: credential was not updated';
  end if;


  if exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key in (
      v_name_bucket,
      v_pair_bucket
    )
  ) then

    raise exception
      'TEST_FAILED: subject rate limits remain';
  end if;


  -- IP-wide protection must remain.
  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_ip_bucket
      and r.subject_key is null
  ) then

    raise exception
      'TEST_FAILED: atomic reset deleted IP-wide rate limit';
  end if;


  -- ==========================================================
  -- CONCURRENT NAME CHANGE GUARD
  --
  -- Wrong expected login name must fail BEFORE changing PIN
  -- or clearing rate limits.
  -- ==========================================================

  perform
    public.auth_record_login_failure_scoped(
      v_name_bucket,
      v_subject_key,
      900,
      10,
      900
    );


  v_denied := false;


  begin

    perform
      public.admin_reset_account_pin_and_unlock_data(
        v_master_id,
        v_target_id,
        v_original_hash,
        v_original_fingerprint,
        v_login_name || '__STALE',
        v_subject_key
      );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LOGIN_NAME_CHANGED_RETRY' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: stale login-name context accepted';
  end if;


  -- Credential must still contain new values.
  if not exists (
    select 1
    from private.login_credentials c
    where c.profile_id = v_target_id
      and c.pin_hash = v_new_hash
      and c.pin_fingerprint =
          v_new_fingerprint
  ) then

    raise exception
      'TEST_FAILED: stale-context failure mutated credential';
  end if;


  -- Rate limit must also remain because entire operation failed.
  if not exists (
    select 1
    from private.login_rate_limits r
    where r.bucket_key = v_name_bucket
      and r.subject_key = v_subject_key
  ) then

    raise exception
      'TEST_FAILED: stale-context failure still cleared rate limit';
  end if;

end;
$$;


select
  'PASS: atomic PIN reset+unlock / context authorization path / credential lock / stale-name race guard / subject clear / IP protection'
  as test_result;

rollback;
