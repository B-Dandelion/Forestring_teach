-- ============================================================
-- Forestring v3
-- PIN reset foundation + subject-scoped login rate limits
--
-- Goals:
-- - admin PIN reset is atomic at credential level
-- - no raw PIN enters PostgreSQL
-- - no PIN/hash/fingerprint enters audit history
-- - same visible name + same PIN remains globally forbidden
-- - PIN reset can clear only that login name's rate-limit rows
-- - IP-wide rate limits remain untouched
-- ============================================================


-- ============================================================
-- 1. RATE-LIMIT SUBJECT GROUP
--
-- subject_key:
--   HMAC(
--     RATE_LIMIT_PEPPER,
--     "subject:<normalized login name>"
--   )
--
-- Raw name is never stored here.
-- ============================================================

alter table private.login_rate_limits
add column subject_key text;


alter table private.login_rate_limits
add constraint login_rate_limits_subject_key_format
check (
  subject_key is null
  or subject_key ~ '^[0-9a-f]{64}$'
);


create index login_rate_limits_subject_key_idx
on private.login_rate_limits(subject_key)
where subject_key is not null;



-- ============================================================
-- 2. SUBJECT-AWARE FAILURE RECORDING
--
-- Keep the old auth_record_login_failure() temporarily.
-- The currently deployed login Edge still depends on it until
-- the new Edge version is deployed.
-- ============================================================

create or replace function
public.auth_record_login_failure_scoped(
  p_bucket_key text,
  p_subject_key text,
  p_window_seconds integer,
  p_max_attempts integer,
  p_lock_seconds integer
)
returns table (
  failed_attempts integer,
  window_started_at timestamptz,
  locked_until timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz :=
    pg_catalog.now();

  v_row private.login_rate_limits%rowtype;

  v_failed integer;
  v_window_started timestamptz;
  v_locked_until timestamptz;
begin

  if p_bucket_key is null
     or p_bucket_key !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_RATE_LIMIT_BUCKET';
  end if;


  if p_subject_key is not null
     and p_subject_key !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_RATE_LIMIT_SUBJECT';
  end if;


  if p_window_seconds <= 0
     or p_max_attempts <= 0
     or p_lock_seconds <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_RATE_LIMIT_POLICY';
  end if;


  insert into private.login_rate_limits (
    bucket_key,
    subject_key,
    failed_attempts,
    window_started_at,
    locked_until
  )
  values (
    p_bucket_key,
    p_subject_key,
    0,
    v_now,
    null
  )
  on conflict (bucket_key)
  do nothing;


  select *
  into v_row

  from private.login_rate_limits r

  where r.bucket_key =
        p_bucket_key

  for update;


  -- Existing pre-migration rows have subject_key NULL.
  -- They may safely acquire their subject on first use.
  if v_row.subject_key is null
     and p_subject_key is not null then

    update private.login_rate_limits
    set subject_key =
        p_subject_key

    where bucket_key =
          p_bucket_key;


    v_row.subject_key :=
      p_subject_key;

  elsif v_row.subject_key is not null
        and v_row.subject_key
            is distinct from
            p_subject_key then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_RATE_LIMIT_SCOPE_MISMATCH';

  end if;


  if v_row.locked_until is not null
     and v_row.locked_until > v_now then

    return query
    select
      v_row.failed_attempts,
      v_row.window_started_at,
      v_row.locked_until;

    return;
  end if;


  if v_now >= (
    v_row.window_started_at
    + pg_catalog.make_interval(
        secs => p_window_seconds
      )
  ) then

    v_failed := 1;
    v_window_started := v_now;

  else

    v_failed :=
      v_row.failed_attempts + 1;

    v_window_started :=
      v_row.window_started_at;

  end if;


  if v_failed >=
     p_max_attempts then

    v_locked_until :=
      v_now
      + pg_catalog.make_interval(
          secs => p_lock_seconds
        );

  else

    v_locked_until :=
      null;

  end if;


  update private.login_rate_limits
  set
    failed_attempts =
      v_failed,

    window_started_at =
      v_window_started,

    locked_until =
      v_locked_until

  where bucket_key =
        p_bucket_key;


  return query
  select
    v_failed,
    v_window_started,
    v_locked_until;

end;
$$;


revoke all
on function
public.auth_record_login_failure_scoped(
  text,
  text,
  integer,
  integer,
  integer
)
from public, anon, authenticated;


grant execute
on function
public.auth_record_login_failure_scoped(
  text,
  text,
  integer,
  integer,
  integer
)
to service_role;



-- ============================================================
-- 3. CLEAR ALL NAME/PAIR RATE LIMITS FOR ONE SUBJECT
--
-- IP-only rows have subject_key NULL and are never deleted.
-- ============================================================

create or replace function
public.auth_clear_login_rate_limits_for_subject(
  p_subject_key text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin

  if p_subject_key is null
     or p_subject_key !~ '^[0-9a-f]{64}$' then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_RATE_LIMIT_SUBJECT';

  end if;


  delete
  from private.login_rate_limits r

  where r.subject_key =
        p_subject_key;


  get diagnostics
    v_deleted =
      row_count;


  return v_deleted;

end;
$$;


revoke all
on function
public.auth_clear_login_rate_limits_for_subject(
  text
)
from public, anon, authenticated;


grant execute
on function
public.auth_clear_login_rate_limits_for_subject(
  text
)
to service_role;



-- ============================================================
-- 4. SERVER-ONLY ATOMIC PIN RESET
--
-- Raw PIN is NEVER passed here.
--
-- Edge sends:
--   bcrypt hash
--   HMAC fingerprint
--
-- Same UUID / hidden Auth identity / visible name are preserved.
-- ============================================================

create or replace function
public.admin_reset_account_pin_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_pin_hash text,
  p_pin_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_target_role public.user_role;
  v_target_branch_id uuid;
  v_target_active boolean;
  v_target_display_name text;

  v_login_name_normalized text;
  v_previous_fingerprint text;

  v_credential_changed boolean;

  v_today date;
begin

  -- ==========================================================
  -- ACTOR
  --
  -- Lock actor so role/is_active cannot change halfway through
  -- this privileged operation.
  -- ==========================================================

  if p_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTOR_REQUIRED';
  end if;


  select
    p.role,
    p.branch_id

  into
    v_actor_role,
    v_actor_branch_id

  from public.profiles p

  where p.id =
        p_actor_id

    and p.is_active = true

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_ACTOR_REQUIRED';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PIN_RESET_FORBIDDEN';

  end if;


  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PROFILE_ID_REQUIRED';
  end if;


  if p_pin_hash is null
     or length(btrim(p_pin_hash)) = 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_PIN_HASH';

  end if;


  if p_pin_fingerprint is null
     or p_pin_fingerprint
        !~ '^[0-9a-f]{64}$' then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_PIN_FINGERPRINT';

  end if;


  -- ==========================================================
  -- TARGET
  -- ==========================================================

  select
    p.role,
    p.branch_id,
    p.is_active,
    p.display_name

  into
    v_target_role,
    v_target_branch_id,
    v_target_active,
    v_target_display_name

  from public.profiles p

  where p.id =
        p_profile_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PROFILE_NOT_FOUND';
  end if;


  -- ==========================================================
  -- AUTHORIZATION
  --
  -- master:
  --   any account
  --
  -- manager:
  --   self
  --   own-branch teacher
  --   own-branch student
  --
  -- manager may NOT reset another manager/master.
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role

     and p_actor_id <>
         p_profile_id then

    if v_target_role not in (
      'teacher'::public.user_role,
      'student'::public.user_role
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_PIN_RESET_FORBIDDEN';

    end if;


    if v_actor_branch_id is null
       or v_target_branch_id
          is distinct from
          v_actor_branch_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;

  end if;


  -- ==========================================================
  -- CREDENTIAL
  -- ==========================================================

  select
    c.login_name_normalized,
    c.pin_fingerprint

  into
    v_login_name_normalized,
    v_previous_fingerprint

  from private.login_credentials c

  where c.profile_id =
        p_profile_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LOGIN_CREDENTIAL_REQUIRED';
  end if;


  v_credential_changed :=
    v_previous_fingerprint
    is distinct from
    p_pin_fingerprint;


  -- ==========================================================
  -- UPDATE
  --
  -- If fingerprint is identical, do not replace the bcrypt hash.
  -- The request is still audited because PIN reset is a
  -- privileged security operation and may also be used to clear
  -- a login lock.
  -- ==========================================================

  if v_credential_changed then

    begin

      update private.login_credentials
      set
        pin_hash =
          p_pin_hash,

        pin_fingerprint =
          p_pin_fingerprint

      where profile_id =
            p_profile_id;


    exception
      when unique_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_NAME_PIN_ALREADY_IN_USE';

    end;

  end if;


  -- ==========================================================
  -- AUDIT
  --
  -- NEVER store:
  --   raw PIN
  --   PIN hash
  --   PIN fingerprint
  -- ==========================================================

  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_profile_id,
    v_target_branch_id,
    null,
    'ACCOUNT_PIN_RESET',
    v_today,
    p_actor_id,

    jsonb_build_object(
      'credentialChanged',
        v_credential_changed,

      'targetRole',
        v_target_role,

      'targetWasActive',
        v_target_active
    )
  );


  return jsonb_build_object(
    'changed',
      v_credential_changed,

    'profileId',
      p_profile_id,

    'displayName',
      v_target_display_name,

    'loginNameNormalized',
      v_login_name_normalized,

    'role',
      v_target_role,

    'branchId',
      v_target_branch_id,

    'isActive',
      v_target_active
  );

end;
$$;


revoke all
on function
public.admin_reset_account_pin_data(
  uuid,
  uuid,
  text,
  text
)
from public, anon, authenticated;


grant execute
on function
public.admin_reset_account_pin_data(
  uuid,
  uuid,
  text,
  text
)
to service_role;


comment on function
public.admin_reset_account_pin_data(
  uuid,
  uuid,
  text,
  text
) is
  'Server-only master/manager PIN reset. Preserves UUID/name/Auth identity, never records PIN material in audit, and returns normalized login name so the Edge layer can clear subject-scoped login rate limits.';