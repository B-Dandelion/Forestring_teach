-- ============================================================
-- Forestring v3
-- Teacher <-> Manager role transition
--
-- Same UUID.
-- Same teachers row.
-- Same branch.
-- Same assignments / lessons / work hours.
--
-- Only authorization role changes.
-- ============================================================


-- ============================================================
-- 1. HARDEN TEACHER ENTITY ROLE INTEGRITY
--
-- teachers row is valid for:
--   teacher
--   manager
--
-- students remain handled by the existing student integrity
-- trigger/function.
-- ============================================================

create or replace function
public.assert_teacher_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_role public.user_role;
begin

  select p.role
  into v_role

  from public.profiles p

  where p.id =
        new.id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PROFILE_NOT_FOUND';
  end if;


  if v_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_TEACHER_ENTITY_ROLE';

  end if;


  return new;

end;
$$;


drop trigger if exists
  teachers_assert_profile_role
on public.teachers;


create trigger teachers_assert_profile_role
before insert
or update of id
on public.teachers
for each row
execute function
  public.assert_teacher_profile_role();



-- ============================================================
-- 2. CHANGE STAFF ROLE
-- ============================================================

create or replace function public.change_staff_role(
  p_staff_id uuid,
  p_new_role public.user_role
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_current_role public.user_role;
  v_branch_id uuid;
  v_profile_active boolean;

  v_today date;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_actor_id

      and p.role =
          'master'::public.user_role

      and p.is_active = true
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MASTER_REQUIRED';

  end if;


  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_staff_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_ID_REQUIRED';
  end if;


  if p_new_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_STAFF_ROLE';

  end if;


  -- ==========================================================
  -- LOCK TARGET
  -- ==========================================================

  select
    p.role,
    p.branch_id,
    p.is_active

  into
    v_current_role,
    v_branch_id,
    v_profile_active

  from public.profiles p

  where p.id =
        p_staff_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_NOT_FOUND';
  end if;


  if v_current_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_NOT_STAFF';

  end if;


  if not v_profile_active then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STAFF_REQUIRED';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_BRANCH_REQUIRED';
  end if;


  -- Every teacher/manager must retain the same teacher entity.
  if not exists (
    select 1

    from public.teachers t

    where t.id =
          p_staff_id
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_ENTITY_REQUIRED';
  end if;


  -- ==========================================================
  -- IDEMPOTENT
  -- ==========================================================

  if v_current_role =
     p_new_role then

    return jsonb_build_object(
      'changed',
        false,

      'staffId',
        p_staff_id,

      'branchId',
        v_branch_id,

      'role',
        v_current_role
    );

  end if;


  -- ==========================================================
  -- ROLE CHANGE ONLY
  --
  -- DO NOT mutate:
  --   teachers
  --   teacher_work_hours
  --   blocked_periods
  --   assignments
  --   lesson_series
  --   lessons
  -- ==========================================================

  update public.profiles
  set role =
      p_new_role

  where id =
        p_staff_id;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- AUDIT
  -- ==========================================================

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
    p_staff_id,
    v_branch_id,
    null,
    'STAFF_ROLE_CHANGED',
    v_today,
    v_actor_id,

    jsonb_build_object(
      'previousRole',
        v_current_role,

      'newRole',
        p_new_role
    )
  );


  return jsonb_build_object(
    'changed',
      true,

    'staffId',
      p_staff_id,

    'branchId',
      v_branch_id,

    'previousRole',
      v_current_role,

    'role',
      p_new_role
  );

end;
$$;


revoke all
on function public.change_staff_role(
  uuid,
  public.user_role
)
from public, anon;


grant execute
on function public.change_staff_role(
  uuid,
  public.user_role
)
to authenticated;


comment on function public.change_staff_role(
  uuid,
  public.user_role
) is
  'Master-only teacher/manager role transition. Preserves the same UUID, teacher entity, branch, work hours, assignments, schedules and lessons.';