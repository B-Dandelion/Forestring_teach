-- ============================================================
-- Forestring v3
-- Server-only teacher account creation transaction
--
-- Called only by the trusted master Edge Function.
--
-- Auth user creation happens in the Edge Function first.
-- This RPC atomically creates:
--
-- profiles
-- teachers
-- login credential
-- teacher_work_hours
-- ============================================================

create or replace function public.admin_create_teacher_account_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_work_hours jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;

  v_weekday smallint;
  v_start_time time;
  v_end_time time;
begin

  -- ----------------------------------------------------------
  -- MASTER ONLY
  -- ----------------------------------------------------------

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_actor_id
      and p.role = 'master'::public.user_role
      and p.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;


  -- ----------------------------------------------------------
  -- BASIC VALIDATION
  -- ----------------------------------------------------------

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


  if jsonb_typeof(
       coalesce(p_work_hours, '[]'::jsonb)
     ) <> 'array' then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_WORK_HOURS';
  end if;


  -- ----------------------------------------------------------
  -- PROFILE
  -- ----------------------------------------------------------

  insert into public.profiles (
    id,
    display_name,
    role,
    is_active
  )
  values (
    p_profile_id,
    btrim(p_display_name),
    'teacher'::public.user_role,
    true
  );


  -- ----------------------------------------------------------
  -- TEACHER
  -- ----------------------------------------------------------

  insert into public.teachers (
    id
  )
  values (
    p_profile_id
  );


  -- ----------------------------------------------------------
  -- LOGIN CREDENTIAL
  --
  -- Raw PIN never reaches PostgreSQL.
  -- ----------------------------------------------------------

  perform public.auth_upsert_login_credential(
    p_profile_id,
    p_login_name_normalized,
    p_pin_hash,
    p_pin_fingerprint
  );


  -- ----------------------------------------------------------
  -- WORK HOURS
  --
  -- Expected JSON:
  --
  -- [
  --   {
  --     "weekday": 1,
  --     "startTime": "10:00",
  --     "endTime": "13:00"
  --   },
  --   {
  --     "weekday": 1,
  --     "startTime": "15:00",
  --     "endTime": "19:00"
  --   }
  -- ]
  --
  -- Multiple segments per weekday are allowed.
  -- ----------------------------------------------------------

  for v_item in
    select value
    from jsonb_array_elements(
      coalesce(p_work_hours, '[]'::jsonb)
    )
  loop

    begin
      v_weekday :=
        (v_item ->> 'weekday')::smallint;

      v_start_time :=
        (v_item ->> 'startTime')::time;

      v_end_time :=
        (v_item ->> 'endTime')::time;

    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_INVALID_WORK_HOURS';
    end;


    if v_weekday not between 1 and 7 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_WORK_WEEKDAY';
    end if;


    if v_start_time >= v_end_time then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_INVALID_WORK_TIME_RANGE';
    end if;


    -- Forestring's smallest scheduling unit is 15 minutes.
    --
    -- Work-hour boundaries are therefore also kept on the
    -- same 15-minute grid.
    if (
      extract(minute from v_start_time)::integer % 15 <> 0
      or
      extract(minute from v_end_time)::integer % 15 <> 0
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_WORK_TIME_NOT_15_MINUTE_ALIGNED';
    end if;


    insert into public.teacher_work_hours (
      teacher_id,
      weekday,
      start_time,
      end_time
    )
    values (
      p_profile_id,
      v_weekday,
      v_start_time,
      v_end_time
    );

  end loop;


  return p_profile_id;


exception

  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_NAME_PIN_ALREADY_IN_USE';


  when exclusion_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WORK_HOURS_OVERLAP';

end;
$$;


-- ============================================================
-- SERVER ONLY
-- ============================================================

revoke all
on function public.admin_create_teacher_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
)
from public, anon, authenticated;


grant execute
on function public.admin_create_teacher_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
)
to service_role;
