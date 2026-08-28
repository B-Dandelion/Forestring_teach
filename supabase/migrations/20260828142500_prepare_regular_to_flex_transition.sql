-- Prepare a regular -> flex transition at a semester boundary without rewriting
-- historical semesters. The global students.student_type remains unchanged until
-- the normal semester transition runs on the target semester start date.
--
-- Existing target/future regular materialization is canceled/revoked and kept as
-- history; the same semester plans are converted to flex plans and flex rights are
-- materialized in advance. Normal semester automation then flips student_type on
-- the effective date.

create or replace function public.prepare_student_flex_transition(
  p_student_id uuid,
  p_target_semester_id uuid,
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
  v_student_status public.student_status;
  v_student_type public.student_type;
  v_today date;
  v_target_start date;
  v_target_end date;
  v_source_plan_id uuid;
  v_source_semester_id uuid;
  v_plan record;
  v_lesson record;
  v_materialization jsonb;
  v_plan_count integer := 0;
  v_regular_lesson_canceled_count integer := 0;
  v_regular_right_revoked_count integer := 0;
  v_flex_right_inserted_count integer := 0;
  v_closed_slot_count integer := 0;
  v_tombstoned_slot_count integer := 0;
  v_closed_series_count integer := 0;
  v_tombstoned_series_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found or v_actor_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STAFF_REQUIRED';
  end if;

  if p_base_right_count is null or p_base_right_count <= 0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_FLEX_RIGHT_COUNT';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_FLEX_DURATION';
  end if;

  select p.branch_id, s.status, s.student_type
  into v_student_branch_id, v_student_status, v_student_type
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
    and p.is_active = true
  for update of s;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_STUDENT_REQUIRED';
  end if;

  if v_student_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select e.starts_on, e.ends_on
  into v_target_start, v_target_end
  from private.get_effective_semester_bounds(v_student_branch_id, p_target_semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  -- Type changes are deliberately semester-boundary operations. Mid-semester
  -- conversion would mix two entitlement policies in one semester.
  if v_target_start <= v_today then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_TRANSITION_REQUIRES_FUTURE_SEMESTER';
  end if;

  -- The immediately preceding active semester is the transition source.
  select sp.id, sp.semester_id
  into v_source_plan_id, v_source_semester_id
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(sp.branch_id, sp.semester_id) e
  where sp.student_id = p_student_id
    and sp.branch_id = v_student_branch_id
    and sp.status = 'active'::public.student_semester_plan_status
    and e.ends_on = v_target_start - 1
  order by e.starts_on desc
  limit 1;

  if v_source_plan_id is null then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_TRANSITION_SOURCE_PLAN_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.id = v_source_plan_id
      and sp.student_type_snapshot = 'regular'::public.student_type
  ) then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_TRANSITION_SOURCE_NOT_REGULAR';
  end if;

  -- Close logical recurring rules at the day before the target semester.
  update public.lesson_series ls
  set effective_until = v_target_start - 1
  where ls.student_id = p_student_id
    and ls.branch_id = v_student_branch_id
    and ls.effective_from < v_target_start
    and (ls.effective_until is null or ls.effective_until >= v_target_start);
  get diagnostics v_closed_series_count = row_count;

  update public.regular_schedule_slots rs
  set ends_on = v_target_start - 1
  where rs.student_id = p_student_id
    and rs.branch_id = v_student_branch_id
    and rs.starts_on < v_target_start
    and (rs.ends_on is null or rs.ends_on >= v_target_start);
  get diagnostics v_closed_slot_count = row_count;

  -- Pure-future rule rows can remain as historical identities because rights and
  -- canceled lessons may reference them. Bound them to their own start date so
  -- they cannot stay open-ended or materialize future regular lessons.
  update public.lesson_series ls
  set effective_until = ls.effective_from
  where ls.student_id = p_student_id
    and ls.branch_id = v_student_branch_id
    and ls.effective_from >= v_target_start
    and (ls.effective_until is null or ls.effective_until > ls.effective_from);
  get diagnostics v_tombstoned_series_count = row_count;

  update public.regular_schedule_slots rs
  set ends_on = rs.starts_on
  where rs.student_id = p_student_id
    and rs.branch_id = v_student_branch_id
    and rs.starts_on >= v_target_start
    and (rs.ends_on is null or rs.ends_on > rs.starts_on);
  get diagnostics v_tombstoned_slot_count = row_count;

  -- Cancel any still-scheduled regular lessons on/after the flex effective date.
  -- Use the canonical academy cancellation path so cancellation history remains
  -- complete; the returned regular rights are revoked immediately afterward.
  for v_lesson in
    select l.id
    from public.lessons l
    where l.student_id = p_student_id
      and l.lesson_type = 'regular'::public.lesson_type
      and l.status = 'scheduled'::public.lesson_status
      and (l.starts_at at time zone 'Asia/Seoul')::date >= v_target_start
      and l.lesson_right_id is not null
    order by l.starts_at, l.id
    for update
  loop
    perform public.cancel_lesson(v_lesson.id, 'student_type_changed_to_flex');
    v_regular_lesson_canceled_count := v_regular_lesson_canceled_count + 1;
  end loop;

  -- Old regular entitlements for target/future semesters no longer represent the
  -- student's contract. Keep the rows for history but make them unusable.
  update public.lesson_rights r
  set
    status = 'revoked'::public.lesson_right_status,
    revoked_at = coalesce(r.revoked_at, pg_catalog.now()),
    reserved_at = null
  where r.student_id = p_student_id
    and r.origin = 'regular_base'::public.lesson_right_origin
    and r.source_semester_id in (
      select sp.semester_id
      from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id, sp.semester_id) e
      where sp.student_id = p_student_id
        and sp.branch_id = v_student_branch_id
        and e.starts_on >= v_target_start
    )
    and r.status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );
  get diagnostics v_regular_right_revoked_count = row_count;

  -- Convert every already-created target/future plan. If farther future plans do
  -- not exist yet, normal automation will create them as flex after student_type
  -- changes on the target semester start.
  for v_plan in
    select sp.id, sp.semester_id, sp.status, e.starts_on
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(sp.branch_id, sp.semester_id) e
    where sp.student_id = p_student_id
      and sp.branch_id = v_student_branch_id
      and e.starts_on >= v_target_start
      and sp.status <> 'completed'::public.student_semester_plan_status
    order by e.starts_on
    for update of sp
  loop
    update public.student_semester_plans
    set
      student_type_snapshot = 'flex'::public.student_type,
      flex_base_right_count = p_base_right_count,
      flex_duration_minutes = p_duration_minutes,
      updated_by = v_actor_id
    where id = v_plan.id;

    -- Existing pre-materialized plans are active. A planned plan can be activated
    -- through the canonical plan activation RPC.
    if v_plan.status = 'active'::public.student_semester_plan_status then
      v_materialization := public.materialize_flex_base_rights(v_plan.id);
    else
      v_materialization := public.activate_student_semester_plan(v_plan.id);
    end if;

    v_flex_right_inserted_count := v_flex_right_inserted_count
      + coalesce((v_materialization->>'insertedCount')::integer, 0)
      + coalesce((v_materialization->'materialization'->>'insertedCount')::integer, 0);

    v_plan_count := v_plan_count + 1;
  end loop;

  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.student_id = p_student_id
      and sp.semester_id = p_target_semester_id
      and sp.student_type_snapshot = 'flex'::public.student_type
  ) then
    -- Target plan did not exist yet. Create it directly as a planned flex plan,
    -- then activate/materialize through the canonical RPC.
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
      p_target_semester_id,
      v_student_branch_id,
      'flex'::public.student_type,
      p_base_right_count,
      p_duration_minutes,
      'planned'::public.student_semester_plan_status,
      v_actor_id,
      v_actor_id
    )
    returning id into v_source_plan_id;

    v_materialization := public.activate_student_semester_plan(v_source_plan_id);
    v_flex_right_inserted_count := v_flex_right_inserted_count
      + coalesce((v_materialization->'materialization'->>'insertedCount')::integer, 0);
    v_plan_count := v_plan_count + 1;
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
    p_student_id,
    v_student_branch_id,
    p_target_semester_id,
    'STUDENT_FLEX_TRANSITION_PREPARED',
    v_target_start,
    v_actor_id,
    jsonb_build_object(
      'targetSemesterId', p_target_semester_id,
      'targetStartsOn', v_target_start,
      'baseRightCount', p_base_right_count,
      'durationMinutes', p_duration_minutes,
      'convertedPlanCount', v_plan_count,
      'regularLessonCanceledCount', v_regular_lesson_canceled_count,
      'regularRightRevokedCount', v_regular_right_revoked_count,
      'flexRightInsertedCount', v_flex_right_inserted_count,
      'closedRegularSlotCount', v_closed_slot_count,
      'tombstonedFutureSlotCount', v_tombstoned_slot_count,
      'closedRegularSeriesCount', v_closed_series_count,
      'tombstonedFutureSeriesCount', v_tombstoned_series_count,
      'studentTypeChangesOnSemesterTransition', true
    )
  );

  return jsonb_build_object(
    'changed', true,
    'studentId', p_student_id,
    'effectiveOn', v_target_start,
    'targetSemesterId', p_target_semester_id,
    'baseRightCount', p_base_right_count,
    'durationMinutes', p_duration_minutes,
    'convertedPlanCount', v_plan_count,
    'regularLessonCanceledCount', v_regular_lesson_canceled_count,
    'regularRightRevokedCount', v_regular_right_revoked_count,
    'flexRightInsertedCount', v_flex_right_inserted_count,
    'studentTypeChangesOnSemesterTransition', true
  );
end;
$function$;

revoke all on function public.prepare_student_flex_transition(uuid,uuid,integer,integer) from public;
grant execute on function public.prepare_student_flex_transition(uuid,uuid,integer,integer) to authenticated;
