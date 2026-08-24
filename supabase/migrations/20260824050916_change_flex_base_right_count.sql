-- ============================================================
-- Forestring v3
-- Change the current active flex semester's base right count
-- ============================================================

create or replace function public.change_flex_base_right_count(
  p_student_id uuid,
  p_new_base_right_count integer
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
  v_student_profile_active boolean;
  v_student_status public.student_status;
  v_student_type public.student_type;

  v_plan public.student_semester_plans%rowtype;
  v_old_base_right_count integer;
  v_old_cancellation_limit integer;
  v_new_cancellation_limit integer;
  v_old_carryover_cap integer;
  v_new_carryover_cap integer;

  v_existing_right_count integer;
  v_invalid_right_count integer;
  v_tail_right_count integer;
  v_blocked_tail_count integer;
  v_counted_cancellation_count integer;

  v_inserted_count integer := 0;
  v_removed_count integer := 0;
  v_inserted_right_ids jsonb := '[]'::jsonb;
  v_removed_right_ids jsonb := '[]'::jsonb;
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

  if p_new_base_right_count is null
     or p_new_base_right_count <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FLEX_RIGHT_COUNT';
  end if;

  select
    p.branch_id,
    p.is_active,
    s.status,
    s.student_type
  into
    v_student_branch_id,
    v_student_profile_active,
    v_student_status,
    v_student_type
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_profile_active <> true
     or v_student_status <>
        'active'::public.student_status then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'flex'::public.student_type then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_STUDENT_REQUIRED';
  end if;

  select sp.*
  into v_plan
  from public.student_semester_plans sp
  where sp.student_id = p_student_id
    and sp.student_type_snapshot = 'flex'::public.student_type
    and sp.status = 'active'::public.student_semester_plan_status
  order by sp.updated_at desc, sp.created_at desc
  limit 1
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_FLEX_PLAN_REQUIRED';
  end if;

  if v_plan.flex_base_right_count is null
     or v_plan.flex_duration_minutes is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';
  end if;

  if v_student_branch_id is distinct from v_plan.branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_PLAN_BRANCH_MISMATCH';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_plan.branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  v_old_base_right_count := v_plan.flex_base_right_count;
  v_old_cancellation_limit :=
    floor(v_old_base_right_count::numeric / 4)::integer * 2;
  v_new_cancellation_limit :=
    floor(p_new_base_right_count::numeric / 4)::integer * 2;
  v_old_carryover_cap :=
    floor(v_old_base_right_count::numeric / 4)::integer;
  v_new_carryover_cap :=
    floor(p_new_base_right_count::numeric / 4)::integer;

  if p_new_base_right_count = v_old_base_right_count then
    return jsonb_build_object(
      'changed', false,
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'semesterId', v_plan.semester_id,
      'oldBaseRightCount', v_old_base_right_count,
      'newBaseRightCount', p_new_base_right_count,
      'insertedCount', 0,
      'removedCount', 0,
      'cancellationLimit', v_new_cancellation_limit,
      'carryoverCap', v_new_carryover_cap
    );
  end if;

  -- Lock all base rights so booking/cancellation cannot race a decrease.
  perform 1
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin
  order by r.sequence_no
  for update;

  select
    count(*)::integer,
    count(*) filter (
      where r.branch_id is distinct from v_plan.branch_id
         or r.usable_semester_id is distinct from v_plan.semester_id
         or r.duration_minutes is distinct from v_plan.flex_duration_minutes
         or r.sequence_no < 1
         or r.sequence_no > v_old_base_right_count
    )::integer
  into v_existing_right_count, v_invalid_right_count
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin;

  if v_existing_right_count <> v_old_base_right_count
     or v_invalid_right_count > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_RIGHTS_PLAN_MISMATCH';
  end if;

  select count(*)::integer
  into v_counted_cancellation_count
  from public.lesson_cancellation_events e
  join public.lesson_rights r on r.id = e.lesson_right_id
  where e.student_id = v_plan.student_id
    and e.origin = 'student'::public.lesson_cancellation_origin
    and e.counts_toward_limit = true
    and r.origin = 'flex_base'::public.lesson_right_origin
    and r.source_semester_id = v_plan.semester_id;

  if v_counted_cancellation_count > v_new_cancellation_limit then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_RIGHT_COUNT_BELOW_USED_CANCELLATION_QUOTA';
  end if;

  if p_new_base_right_count < v_old_base_right_count then
    select
      count(*)::integer,
      count(*) filter (
        where r.status <> 'available'::public.lesson_right_status
           or exists (
             select 1
             from public.lessons l
             where l.lesson_right_id = r.id
           )
           or exists (
             select 1
             from public.lesson_cancellation_events e
             where e.lesson_right_id = r.id
           )
           or exists (
             select 1
             from public.lesson_rights carried
             where carried.source_right_id = r.id
           )
      )::integer
    into v_tail_right_count, v_blocked_tail_count
    from public.lesson_rights r
    where r.student_id = v_plan.student_id
      and r.source_semester_id = v_plan.semester_id
      and r.origin = 'flex_base'::public.lesson_right_origin
      and r.sequence_no > p_new_base_right_count;

    if v_tail_right_count <>
       v_old_base_right_count - p_new_base_right_count
       or v_blocked_tail_count > 0 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_FLEX_RIGHT_COUNT_DECREASE_BLOCKED';
    end if;

    with removed as (
      delete from public.lesson_rights r
      where r.student_id = v_plan.student_id
        and r.source_semester_id = v_plan.semester_id
        and r.origin = 'flex_base'::public.lesson_right_origin
        and r.sequence_no > p_new_base_right_count
      returning r.id
    )
    select
      count(*)::integer,
      coalesce(jsonb_agg(removed.id), '[]'::jsonb)
    into v_removed_count, v_removed_right_ids
    from removed;
  else
    with inserted as (
      insert into public.lesson_rights (
        student_id,
        branch_id,
        source_semester_id,
        usable_semester_id,
        schedule_slot_id,
        source_right_id,
        origin,
        sequence_no,
        duration_minutes,
        status,
        carryover_count,
        created_by
      )
      select
        v_plan.student_id,
        v_plan.branch_id,
        v_plan.semester_id,
        v_plan.semester_id,
        null,
        null,
        'flex_base'::public.lesson_right_origin,
        sequence_no,
        v_plan.flex_duration_minutes,
        'available'::public.lesson_right_status,
        0,
        v_actor_id
      from generate_series(
        v_old_base_right_count + 1,
        p_new_base_right_count
      ) as sequence_no
      returning id
    )
    select
      count(*)::integer,
      coalesce(jsonb_agg(inserted.id), '[]'::jsonb)
    into v_inserted_count, v_inserted_right_ids
    from inserted;
  end if;

  update public.student_semester_plans
  set
    flex_base_right_count = p_new_base_right_count,
    updated_by = v_actor_id
  where id = v_plan.id;

  select count(*)::integer
  into v_existing_right_count
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin;

  if v_existing_right_count <> p_new_base_right_count then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_RIGHT_COUNT_MISMATCH';
  end if;

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
    v_plan.student_id,
    v_plan.branch_id,
    v_plan.semester_id,
    'FLEX_BASE_RIGHT_COUNT_CHANGED',
    (pg_catalog.now() at time zone 'Asia/Seoul')::date,
    v_actor_id,
    jsonb_build_object(
      'planId', v_plan.id,
      'oldBaseRightCount', v_old_base_right_count,
      'newBaseRightCount', p_new_base_right_count,
      'insertedCount', v_inserted_count,
      'removedCount', v_removed_count,
      'insertedRightIds', v_inserted_right_ids,
      'removedRightIds', v_removed_right_ids,
      'countedStudentCancellations', v_counted_cancellation_count,
      'oldCancellationLimit', v_old_cancellation_limit,
      'newCancellationLimit', v_new_cancellation_limit,
      'oldCarryoverCap', v_old_carryover_cap,
      'newCarryoverCap', v_new_carryover_cap
    )
  );

  return jsonb_build_object(
    'changed', true,
    'planId', v_plan.id,
    'studentId', v_plan.student_id,
    'semesterId', v_plan.semester_id,
    'oldBaseRightCount', v_old_base_right_count,
    'newBaseRightCount', p_new_base_right_count,
    'insertedCount', v_inserted_count,
    'removedCount', v_removed_count,
    'countedStudentCancellations', v_counted_cancellation_count,
    'oldCancellationLimit', v_old_cancellation_limit,
    'newCancellationLimit', v_new_cancellation_limit,
    'oldCarryoverCap', v_old_carryover_cap,
    'newCarryoverCap', v_new_carryover_cap
  );
end;
$function$;

revoke all
on function public.change_flex_base_right_count(uuid, integer)
from public, anon;

grant execute
on function public.change_flex_base_right_count(uuid, integer)
to authenticated;

comment on function public.change_flex_base_right_count(uuid, integer) is
  'Atomically changes an active flex semester base-right count. Increases issue new rights; decreases remove only unused, unreserved, history-free tail rights. The new count cannot undercut already consumed student-cancellation quota. Master or same-branch manager only.';
