-- ============================================================
-- Forestring v3
-- Atomic initial setup for a flex student semester
-- ============================================================

create or replace function public.initialize_flex_student_semester(
  p_student_id uuid,
  p_teacher_id uuid,
  p_semester_id uuid,
  p_base_right_count integer,
  p_duration_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_student_branch_id uuid;
  v_student_type public.student_type;
  v_student_status public.student_status;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_semester_start date;
  v_semester_end date;

  v_plan_id uuid;
  v_activation jsonb;
begin
  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';
  end if;

  select p.branch_id, s.student_type, s.status
  into v_student_branch_id, v_student_type, v_student_status
  from public.students s
  join public.profiles p on p.id = s.id
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

  if v_student_type <> 'flex'::public.student_type then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_STUDENT_REQUIRED';
  end if;

  if v_student_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;

  if p_base_right_count is null or p_base_right_count <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FLEX_RIGHT_COUNT';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FLEX_DURATION';
  end if;

  select p.branch_id, p.is_active, t.withdrawal_date
  into v_teacher_branch_id, v_teacher_active, v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id = t.id
  where t.id = p_teacher_id;

  if not found or v_teacher_active <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_MISMATCH';
  end if;

  select e.starts_on, e.ends_on
  into v_semester_start, v_semester_end
  from private.get_effective_semester_bounds(
    v_student_branch_id,
    p_semester_id
  ) e;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if v_teacher_withdrawal_date is not null
     and v_semester_start >= v_teacher_withdrawal_date then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if exists (
    select 1
    from public.student_semester_plans sp
    where sp.student_id = p_student_id
      and sp.semester_id = p_semester_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_INITIAL_SETUP_ALREADY_EXISTS';
  end if;

  if exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = p_student_id
      and a.starts_on <= v_semester_start
      and (a.ends_on is null or a.ends_on >= v_semester_start)
      and a.teacher_id <> p_teacher_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_PERIOD_OVERLAP';
  end if;

  if not exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = p_student_id
      and a.teacher_id = p_teacher_id
      and a.starts_on <= v_semester_start
      and (a.ends_on is null or a.ends_on >= v_semester_start)
  ) then
    perform public.assign_student_teacher(
      p_student_id,
      p_teacher_id,
      v_semester_start
    );
  end if;

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status,
    created_by,
    updated_by
  )
  values (
    p_student_id,
    p_semester_id,
    v_student_branch_id,
    'flex'::public.student_type,
    p_base_right_count,
    p_duration_minutes,
    'planned'::public.student_semester_plan_status,
    v_actor_id,
    v_actor_id
  )
  returning id into v_plan_id;

  v_activation := public.activate_student_semester_plan(v_plan_id);

  return jsonb_build_object(
    'studentId', p_student_id,
    'semesterId', p_semester_id,
    'teacherId', p_teacher_id,
    'baseRightCount', p_base_right_count,
    'durationMinutes', p_duration_minutes,
    'activation', v_activation
  );
exception
  when exclusion_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_INITIAL_SETUP_CONFLICT';
end;
$function$;

revoke all
on function public.initialize_flex_student_semester(
  uuid,
  uuid,
  uuid,
  integer,
  integer
)
from public, anon;

grant execute
on function public.initialize_flex_student_semester(
  uuid,
  uuid,
  uuid,
  integer,
  integer
)
to authenticated;

comment on function public.initialize_flex_student_semester(
  uuid,
  uuid,
  uuid,
  integer,
  integer
) is
  'Atomically assigns a teacher, creates a flex semester plan, activates it, and materializes the configured flex lesson rights.';
