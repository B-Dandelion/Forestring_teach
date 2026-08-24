-- Master-only manager branch transfer.
-- A manager is also a teacher-capable staff member, so cross-branch transfer
-- is blocked while teaching relationships or future schedules remain.

create or replace function public.change_manager_branch(
  p_manager_id uuid,
  p_branch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_old_branch_id uuid;
  v_old_branch_name text;
  v_new_branch_name text;
  v_is_active boolean;
  v_withdrawal_date date;
  v_today date := ((pg_catalog.now() at time zone 'Asia/Seoul')::date);
  v_assignment_count integer;
  v_series_count integer;
  v_lesson_count integer;
begin
  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.role = 'master'::public.user_role
      and p.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  if p_manager_id is null or p_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_INPUT_REQUIRED';
  end if;

  select p.branch_id, p.is_active, t.withdrawal_date
  into v_old_branch_id, v_is_active, v_withdrawal_date
  from public.profiles p
  join public.teachers t on t.id = p.id
  where p.id = p_manager_id
    and p.role = 'manager'::public.user_role
  for update of p, t;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_NOT_FOUND';
  end if;

  if not v_is_active then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_MANAGER_REQUIRED';
  end if;

  if v_withdrawal_date is not null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_CHANGE_PENDING_DEPARTURE';
  end if;

  select b.name
  into v_new_branch_name
  from public.branches b
  where b.id = p_branch_id
    and b.is_active = true;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_BRANCH_REQUIRED';
  end if;

  if v_old_branch_id = p_branch_id then
    return jsonb_build_object(
      'changed', false,
      'managerId', p_manager_id,
      'branchId', p_branch_id,
      'branchName', v_new_branch_name
    );
  end if;

  select b.name
  into v_old_branch_name
  from public.branches b
  where b.id = v_old_branch_id;

  select count(*)::integer
  into v_assignment_count
  from public.teacher_student_assignments a
  where a.teacher_id = p_manager_id
    and (a.ends_on is null or a.ends_on >= v_today);

  select count(*)::integer
  into v_series_count
  from public.lesson_series s
  where s.teacher_id = p_manager_id
    and (s.effective_until is null or s.effective_until >= v_today);

  select count(*)::integer
  into v_lesson_count
  from public.lessons l
  where l.teacher_id = p_manager_id
    and l.status = 'scheduled'::public.lesson_status
    and l.ends_at > pg_catalog.now();

  if v_assignment_count > 0
     or v_series_count > 0
     or v_lesson_count > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_CHANGE_BLOCKED',
      detail = jsonb_build_object(
        'assignmentCount', v_assignment_count,
        'seriesCount', v_series_count,
        'scheduledLessonCount', v_lesson_count
      )::text;
  end if;

  update public.profiles
  set branch_id = p_branch_id
  where id = p_manager_id;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    p_manager_id,
    p_branch_id,
    null,
    'MANAGER_BRANCH_CHANGED',
    v_today,
    v_actor_id,
    jsonb_build_object(
      'previousBranchId', v_old_branch_id,
      'previousBranchName', v_old_branch_name,
      'newBranchId', p_branch_id,
      'newBranchName', v_new_branch_name
    )
  );

  return jsonb_build_object(
    'changed', true,
    'managerId', p_manager_id,
    'previousBranchId', v_old_branch_id,
    'branchId', p_branch_id,
    'branchName', v_new_branch_name
  );
end;
$$;

revoke all on function public.change_manager_branch(uuid, uuid)
  from public, anon;

grant execute on function public.change_manager_branch(uuid, uuid)
  to authenticated;
