-- ============================================================
-- Forestring v3
-- Atomic PIN reset + subject-scoped login unlock
--
-- Existing admin_reset_account_pin_data() remains the canonical
-- credential mutation implementation.
--
-- Edge Functions must use the wrapper below so credential
-- mutation and rate-limit cleanup occur in ONE DB transaction.
-- ============================================================


-- ============================================================
-- 1. SERVER-ONLY RESET CONTEXT
--
-- Edge needs the CURRENT normalized login name in order to
-- derive:
--
-- HMAC(
--   RATE_LIMIT_PEPPER,
--   "subject:<login name>"
-- )
--
-- Authorization is checked here before exposing even that
-- internal value to the Edge workflow.
-- ============================================================

create or replace function
public.admin_get_account_pin_reset_context(
  p_actor_id uuid,
  p_profile_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_target_role public.user_role;
  v_target_branch_id uuid;

  v_login_name_normalized text;
begin

  -- ==========================================================
  -- ACTOR
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
  where p.id = p_actor_id
    and p.is_active = true;


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
  -- TARGET
  -- ==========================================================

  if p_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PROFILE_ID_REQUIRED';
  end if;


  select
    p.role,
    p.branch_id
  into
    v_target_role,
    v_target_branch_id
  from public.profiles p
  where p.id = p_profile_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PROFILE_NOT_FOUND';
  end if;


  -- ==========================================================
  -- AUTHORIZATION
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
  -- LOGIN NAME
  -- ==========================================================

  select
    c.login_name_normalized
  into
    v_login_name_normalized
  from private.login_credentials c
  where c.profile_id = p_profile_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LOGIN_CREDENTIAL_REQUIRED';
  end if;


  return
    v_login_name_normalized;

end;
$$;


revoke all
on function
public.admin_get_account_pin_reset_context(
  uuid,
  uuid
)
from public, anon, authenticated;


grant execute
on function
public.admin_get_account_pin_reset_context(
  uuid,
  uuid
)
to service_role;



-- ============================================================
-- 2. ATOMIC RESET + UNLOCK WRAPPER
--
-- Flow:
--
-- 1. lock credential
-- 2. verify login name has not changed since Edge context read
-- 3. call already-tested canonical PIN reset
-- 4. delete that login-name subject's rate-limit rows
-- 5. commit everything together
--
-- If ANY step fails, ALL changes roll back.
-- ============================================================

create or replace function
public.admin_reset_account_pin_and_unlock_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_expected_login_name_normalized text,
  p_rate_limit_subject_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_login_name text;

  v_result jsonb;

  v_deleted_rate_limits integer;
begin

  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_expected_login_name_normalized is null
     or length(
       btrim(
         p_expected_login_name_normalized
       )
     ) = 0
     or p_expected_login_name_normalized <>
        btrim(
          p_expected_login_name_normalized
        ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_LOGIN_NAME';

  end if;


  if p_rate_limit_subject_key is null
     or p_rate_limit_subject_key
        !~ '^[0-9a-f]{64}$' then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_RATE_LIMIT_SUBJECT';

  end if;


  -- ==========================================================
  -- LOCK CREDENTIAL
  --
  -- This lock remains until the outer wrapper transaction ends.
  --
  -- Therefore a concurrent account-name change cannot slip
  -- between the name check and PIN mutation.
  -- ==========================================================

  select
    c.login_name_normalized
  into
    v_current_login_name
  from private.login_credentials c
  where c.profile_id = p_profile_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LOGIN_CREDENTIAL_REQUIRED';
  end if;


  -- ==========================================================
  -- RACE GUARD
  --
  -- Edge computed subject_key from the earlier context value.
  --
  -- If the account name changed concurrently, do NOT reset PIN
  -- while clearing the old name's login locks.
  -- ==========================================================

  if v_current_login_name <>
     p_expected_login_name_normalized then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LOGIN_NAME_CHANGED_RETRY';

  end if;


  -- ==========================================================
  -- CANONICAL PIN RESET
  --
  -- This function already performs:
  -- - master/manager authorization
  -- - branch authorization
  -- - profile locking
  -- - credential validation
  -- - name+PIN uniqueness
  -- - audit
  --
  -- Because it is invoked inside this wrapper, everything is
  -- still one PostgreSQL transaction.
  -- ==========================================================

  v_result :=
    public.admin_reset_account_pin_data(
      p_actor_id,
      p_profile_id,
      p_pin_hash,
      p_pin_fingerprint
    );


  -- ==========================================================
  -- SUBJECT UNLOCK
  --
  -- Only name / name+IP rows belonging to this normalized
  -- login-name subject are removed.
  --
  -- IP-only buckets have subject_key NULL and remain untouched.
  -- ==========================================================

  delete
  from private.login_rate_limits r
  where r.subject_key =
        p_rate_limit_subject_key;


  get diagnostics
    v_deleted_rate_limits =
      row_count;


  return
    v_result
    ||
    jsonb_build_object(
      'clearedRateLimitCount',
        v_deleted_rate_limits
    );

end;
$$;


revoke all
on function
public.admin_reset_account_pin_and_unlock_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text
)
from public, anon, authenticated;


grant execute
on function
public.admin_reset_account_pin_and_unlock_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text
)
to service_role;



-- ============================================================
-- 3. OLD RESET FUNCTION IS NOW INTERNAL IMPLEMENTATION ONLY
--
-- Edge Functions must not call it directly anymore.
--
-- SECURITY DEFINER wrapper can still call it because the
-- function owner retains privileges.
-- ============================================================

revoke execute
on function public.admin_reset_account_pin_data(
  uuid,
  uuid,
  text,
  text
)
from service_role;


comment on function public.admin_reset_account_pin_data(
  uuid,
  uuid,
  text,
  text
) is
  'Internal credential mutation helper. Edge callers must use admin_reset_account_pin_and_unlock_data so PIN reset and login unlock are atomic.';


comment on function
public.admin_reset_account_pin_and_unlock_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text
) is
  'Server-only atomic PIN reset and subject-scoped login unlock. Guards against concurrent login-name changes.';