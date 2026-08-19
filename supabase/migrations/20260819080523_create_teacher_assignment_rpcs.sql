-- ============================================================
-- Forestring v3
-- Teacher assignment RPCs
--
-- master:
--   may assign students across branches
--
-- manager:
--   may assign students only inside own branch
--
-- Both regular / flex students may have a teacher.
-- Only recurring lesson_series is forbidden for flex.
-- ============================================================


-- ============================================================
-- ASSIGNABLE TEACHERS
--
-- Includes:
--   normal teacher
--   teaching-enabled manager
--
-- Excludes:
--   teaching_enabled = false
--   inactive profile
--   already withdrawn teacher
--   another branch
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


  -- Manager may inspect candidates only for own branch.
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
    and t.teaching_enabled = true
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
-- ASSIGN STUDENT TO TEACHER
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
  v_teaching_enabled boolean;
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
    t.teaching_enabled,
    t.withdrawal_date
  into
    v_teacher_branch_id,
    v_teacher_active,
    v_teaching_enabled,
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


  if v_teaching_enabled <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHING_DISABLED';
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
  -- Existing DB trigger derives branch_id.
  -- Existing exclusion constraint prevents overlapping
  -- assignment periods for the same student.
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
-- PERMISSIONS
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
