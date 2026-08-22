-- ============================================================
-- Forestring v3
-- Atomic account display/login name update
--
-- Visible display name and login credential name must never
-- diverge.
--
-- PIN hash / fingerprint are preserved.
-- Auth UUID / hidden Auth email are preserved.
-- ============================================================


create or replace function public.admin_update_account_name_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text
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

  v_previous_display_name text;
  v_previous_login_name text;

  v_today date;
begin

  -- ==========================================================
  -- 1. ACTOR
  -- ==========================================================

  if p_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTOR_REQUIRED';
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

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_ACTOR_REQUIRED';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACCOUNT_NAME_UPDATE_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 2. INPUT
  --
  -- Edge performs:
  --   NFC
  --   trim
  --   whitespace collapse
  --
  -- DB additionally refuses divergent display/login names.
  -- ==========================================================

  if p_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROFILE_ID_REQUIRED';
  end if;


  if p_display_name is null
     or length(p_display_name) = 0
     or length(p_display_name) > 100
     or p_display_name <> btrim(p_display_name) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_DISPLAY_NAME';

  end if;


  if p_login_name_normalized is null
     or length(p_login_name_normalized) = 0
     or length(p_login_name_normalized) > 100
     or p_login_name_normalized <>
        btrim(p_login_name_normalized) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_LOGIN_NAME';

  end if;


  -- Forestring currently uses exactly the same normalized value
  -- for visible name and login name.
  if p_display_name <>
     p_login_name_normalized then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACCOUNT_NAME_MISMATCH';

  end if;


  -- ==========================================================
  -- 3. LOCK TARGET PROFILE
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
    v_previous_display_name

  from public.profiles p

  where p.id =
        p_profile_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROFILE_NOT_FOUND';
  end if;


  -- ==========================================================
  -- 4. AUTHORIZATION
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role then

    -- Manager may rename self.
    if p_actor_id <>
       p_profile_id then

      -- Manager may NOT rename master/another manager.
      if v_target_role not in (
        'teacher'::public.user_role,
        'student'::public.user_role
      ) then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_ACCOUNT_NAME_UPDATE_FORBIDDEN';

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

  end if;


  -- ==========================================================
  -- 5. LOCK LOGIN CREDENTIAL
  --
  -- Name update must not silently create a credential row.
  -- Every existing account is expected to already own one.
  -- ==========================================================

  select c.login_name_normalized
  into v_previous_login_name

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


  -- ==========================================================
  -- 6. IDEMPOTENT / ALSO DETECTS PARTIAL LEGACY DIVERGENCE
  --
  -- If either side differs, update BOTH.
  -- ==========================================================

  if v_previous_display_name =
       p_display_name

     and v_previous_login_name =
       p_login_name_normalized then

    return jsonb_build_object(
      'changed',
        false,

      'profileId',
        p_profile_id,

      'displayName',
        v_previous_display_name,

      'role',
        v_target_role,

      'branchId',
        v_target_branch_id,

      'isActive',
        v_target_active
    );

  end if;


  -- ==========================================================
  -- 7. ATOMIC UPDATE
  --
  -- Existing PIN hash / fingerprint remain untouched.
  --
  -- The unique constraint on:
  --   (login_name_normalized, pin_fingerprint)
  --
  -- guarantees same-name + same-PIN collision safety.
  -- ==========================================================

  begin

    update private.login_credentials
    set login_name_normalized =
        p_login_name_normalized

    where profile_id =
          p_profile_id;


    update public.profiles
    set display_name =
        p_display_name

    where id =
          p_profile_id;


  exception
    when unique_violation then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_NAME_PIN_ALREADY_IN_USE';

  end;


  -- ==========================================================
  -- 8. AUDIT
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
    'ACCOUNT_NAME_CHANGED',
    v_today,
    p_actor_id,

    jsonb_build_object(
      'previousDisplayName',
        v_previous_display_name,

      'previousLoginName',
        v_previous_login_name,

      'newDisplayName',
        p_display_name,

      'targetRole',
        v_target_role,

      'targetWasActive',
        v_target_active
    )
  );


  -- ==========================================================
  -- 9. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'profileId',
      p_profile_id,

    'previousDisplayName',
      v_previous_display_name,

    'displayName',
      p_display_name,

    'role',
      v_target_role,

    'branchId',
      v_target_branch_id,

    'isActive',
      v_target_active
  );

end;
$$;


-- ============================================================
-- SERVER ONLY
--
-- Flutter must call the Edge Function.
-- It may not call this RPC directly.
-- ============================================================

revoke all
on function public.admin_update_account_name_data(
  uuid,
  uuid,
  text,
  text
)
from public, anon, authenticated;


grant execute
on function public.admin_update_account_name_data(
  uuid,
  uuid,
  text,
  text
)
to service_role;


comment on function public.admin_update_account_name_data(
  uuid,
  uuid,
  text,
  text
) is
  'Server-only atomic display/login name update. Preserves UUID and PIN credential material while enforcing master/manager authorization and same-name+same-PIN uniqueness.';