-- ============================================================
-- Forestring v3
-- Simplify manager / teacher model
--
-- Final policy:
--
-- - teacher-role profile -> teachers row
-- - manager-role profile -> teachers row ALWAYS
-- - no teaching ON/OFF state
-- - having zero students / zero work hours is valid
-- - work hours describe normal availability only
-- - teacher/manager must still be active and not withdrawn
-- ============================================================


-- ============================================================
-- 1. BACKFILL EXISTING MANAGERS
-- ============================================================

insert into public.teachers (
  id
)
select
  p.id
from public.profiles p
where p.role = 'manager'::public.user_role
  and not exists (
    select 1
    from public.teachers t
    where t.id = p.id
  );


-- ============================================================
-- 2. UPDATE MANAGER CREATION RPC
--
-- p_can_teach is intentionally retained TEMPORARILY so the
-- currently deployed Edge Function does not break.
--
-- It has NO business meaning anymore and is ignored.
--
-- A later cleanup migration will remove this parameter after
-- Edge + Flutter have been updated.
-- ============================================================

create or replace function public.admin_create_manager_account_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_can_teach boolean default false,
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

  -- ==========================================================
  -- MASTER ONLY
  -- ==========================================================

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


  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;


  if jsonb_typeof(
       coalesce(
         p_work_hours,
         '[]'::jsonb
       )
     ) <> 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_WORK_HOURS';
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
    'manager'::public.user_role,
    p_branch_id,
    true
  );


  -- ==========================================================
  -- TEACHER ENTITY
  --
  -- Every manager gets this row.
  -- Zero work hours / zero assigned students is completely valid.
  -- ==========================================================

  insert into public.teachers (
    id
  )
  values (
    p_profile_id
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


  -- ==========================================================
  -- OPTIONAL WORK HOURS
  --
  -- Work hours may be empty.
  -- ==========================================================

  for v_item in
    select value
    from jsonb_array_elements(
      coalesce(
        p_work_hours,
        '[]'::jsonb
      )
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


revoke all
on function public.admin_create_manager_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  boolean,
  jsonb
)
from public, anon, authenticated;


grant execute
on function public.admin_create_manager_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  boolean,
  jsonb
)
to service_role;


comment on function public.admin_create_manager_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  boolean,
  jsonb
) is
  'Creates a manager profile and teacher entity. p_can_teach is deprecated compatibility input and is intentionally ignored.';


-- ============================================================
-- 3. REMOVE TEACHING-ENABLED TRIGGERS
-- ============================================================

drop trigger if exists
  teacher_work_hours_require_enabled_teacher
on public.teacher_work_hours;


drop trigger if exists
  blocked_periods_require_enabled_teacher
on public.blocked_periods;


drop trigger if exists
  teacher_student_assignments_require_enabled_teacher
on public.teacher_student_assignments;


drop trigger if exists
  lesson_series_require_enabled_teacher
on public.lesson_series;


drop trigger if exists
  lessons_require_enabled_teacher
on public.lessons;


-- ============================================================
-- 4. REMOVE TEACHING-ENABLED FUNCTION / COLUMN
-- ============================================================

drop function if exists
  public.assert_teacher_accepts_new_work();


alter table public.teachers
drop column if exists teaching_enabled;


comment on table public.teachers is
  'Teaching-capable staff identity. Teacher-role and manager-role profiles use this row. Having no work hours or assigned students is valid.';


-- ============================================================
-- 5. ASSIGNABLE TEACHERS
--
-- All active teacher entities in the student's branch are valid
-- candidates, including managers.
--
-- Work hours are NOT required merely to become an assigned
-- teacher.
-- ============================================================

create or replace function public.get_assignable_teachers_for_student(
  p_student_id uuid
)
returns table (
  teacher_id uuid,
  display_name text,
  profile_role public.user_role
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_student_branch_id uuid;
  v_student_status public.student_status;

  v_today date;
begin
  v_actor_id :=
    (select auth.uid());

  v_today :=
    (now() at time zone 'Asia/Seoul')::date;


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
  where p.id = v_actor_id
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
      message = 'FORESTRING_ASSIGNMENT_FORBIDDEN';
  end if;


  -- ==========================================================
  -- STUDENT
  -- ==========================================================

  select
    p.branch_id,
    s.status
  into
    v_student_branch_id,
    v_student_status
  from public.students s
  join public.profiles p
    on p.id = s.id
  where s.id = p_student_id
    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_student_status <> 'active'::public.student_status then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_INACTIVE';
  end if;


  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;


  -- ==========================================================
  -- CANDIDATES
  -- ==========================================================

  return query
  select
    t.id,
    p.display_name,
    p.role
  from public.teachers t
  join public.profiles p
    on p.id = t.id
  where p.branch_id = v_student_branch_id
    and p.is_active = true
    and (
      t.withdrawal_date is null
      or t.withdrawal_date > v_today
    )
  order by
    lower(p.display_name),
    p.id;
end;
$$;


-- ============================================================
-- 6. INITIAL TEACHER ASSIGNMENT
-- ============================================================

create or replace function public.assign_student_teacher(
  p_student_id uuid,
  p_teacher_id uuid,
  p_starts_on date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_student_branch_id uuid;
  v_student_status public.student_status;
  v_student_withdrawal_date date;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_assignment_id uuid;
begin
  v_actor_id :=
    (select auth.uid());


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
  where p.id = v_actor_id
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
      message = 'FORESTRING_ASSIGNMENT_FORBIDDEN';
  end if;


  if p_starts_on is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_START_DATE_REQUIRED';
  end if;


  -- ==========================================================
  -- STUDENT
  -- ==========================================================

  select
    p.branch_id,
    s.status,
    s.withdrawal_date
  into
    v_student_branch_id,
    v_student_status,
    v_student_withdrawal_date
  from public.students s
  join public.profiles p
    on p.id = s.id
  where s.id = p_student_id
    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_status <> 'active'::public.student_status then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_INACTIVE';
  end if;


  if v_student_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_student_withdrawal_date is not null
     and p_starts_on >= v_student_withdrawal_date then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_AFTER_STUDENT_WITHDRAWAL';
  end if;


  -- ==========================================================
  -- TEACHER
  -- ==========================================================

  select
    p.branch_id,
    p.is_active,
    t.withdrawal_date
  into
    v_teacher_branch_id,
    v_teacher_active,
    v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p
    on p.id = t.id
  where t.id = p_teacher_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;


  if v_teacher_active <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_INACTIVE';
  end if;


  if v_teacher_withdrawal_date is not null
     and p_starts_on >= v_teacher_withdrawal_date then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;


  -- ==========================================================
  -- BRANCH
  -- ==========================================================

  if v_teacher_branch_id is null
     or v_teacher_branch_id <> v_student_branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_MISMATCH';
  end if;


  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;


  -- ==========================================================
  -- ASSIGN
  --
  -- branch_id is derived by the existing trigger.
  -- overlapping assignment periods remain forbidden.
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    p_teacher_id,
    p_student_id,
    p_starts_on,
    null
  )
  returning id
  into v_assignment_id;


  return v_assignment_id;


exception

  when exclusion_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_PERIOD_OVERLAP';

end;
$$;


-- ============================================================
-- 7. RPC PERMISSIONS
-- ============================================================

revoke all
on function public.get_assignable_teachers_for_student(uuid)
from public, anon;


revoke all
on function public.assign_student_teacher(
  uuid,
  uuid,
  date
)
from public, anon;


grant execute
on function public.get_assignable_teachers_for_student(uuid)
to authenticated, service_role;


grant execute
on function public.assign_student_teacher(
  uuid,
  uuid,
  date
)
to authenticated, service_role;