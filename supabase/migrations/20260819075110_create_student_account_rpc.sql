-- ============================================================
-- Forestring v3
-- Create student account data
--
-- master:
--   may create student in any active branch
--
-- manager:
--   may create student only in own active branch
--
-- Student creation intentionally DOES NOT:
--   - assign teacher
--   - create lesson_series
--   - create lessons
-- ============================================================

create or replace function public.admin_create_student_account_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_student_type public.student_type
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_resolved_branch_id uuid;
begin

  -- ==========================================================
  -- ACTOR
  -- ==========================================================

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
      message = 'FORESTRING_ACTOR_NOT_FOUND';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_CREATE_FORBIDDEN';
  end if;


  -- ==========================================================
  -- BASIC VALIDATION
  -- ==========================================================

  if p_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROFILE_ID_REQUIRED';
  end if;


  if p_display_name is null
     or length(btrim(p_display_name)) = 0
     or length(p_display_name) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_DISPLAY_NAME';
  end if;


  if p_login_name_normalized is null
     or length(btrim(p_login_name_normalized)) = 0
     or p_login_name_normalized <> btrim(p_login_name_normalized) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_LOGIN_NAME';
  end if;


  if p_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_REQUIRED';
  end if;


  if p_student_type is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_TYPE_REQUIRED';
  end if;


  -- ==========================================================
  -- RESOLVE BRANCH
  -- ==========================================================

  if v_actor_role = 'master'::public.user_role then

    v_resolved_branch_id :=
      p_branch_id;


  elsif v_actor_role = 'manager'::public.user_role then

    if v_actor_branch_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MANAGER_BRANCH_REQUIRED';
    end if;


    if p_branch_id <> v_actor_branch_id then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MANAGER_BRANCH_MISMATCH';
    end if;


    v_resolved_branch_id :=
      v_actor_branch_id;

  end if;


  if not exists (
    select 1
    from public.branches b
    where b.id = v_resolved_branch_id
      and b.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;


  -- ==========================================================
  -- PROFILE
  -- ==========================================================

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values (
    p_profile_id,
    btrim(p_display_name),
    'student'::public.user_role,
    v_resolved_branch_id,
    true
  );


  -- ==========================================================
  -- STUDENT
  -- ==========================================================

  insert into public.students (
    id,
    status,
    withdrawal_date,
    student_type
  )
  values (
    p_profile_id,
    'active'::public.student_status,
    null,
    p_student_type
  );


  -- ==========================================================
  -- LOGIN CREDENTIAL
  -- ==========================================================

  perform public.auth_upsert_login_credential(
    p_profile_id,
    p_login_name_normalized,
    p_pin_hash,
    p_pin_fingerprint
  );


  return p_profile_id;


exception

  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_NAME_PIN_ALREADY_IN_USE';

end;
$$;


-- ============================================================
-- SERVER ONLY
-- ============================================================

revoke all
on function public.admin_create_student_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  public.student_type
)
from public, anon, authenticated;


grant execute
on function public.admin_create_student_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  public.student_type
)
to service_role;
