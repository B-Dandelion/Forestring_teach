create or replace function private.require_semester_automation_actor()
returns table(actor_id uuid, actor_role public.user_role, is_system boolean)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role public.user_role;
begin
  if v_uid is null then
    if session_user = 'postgres'
       and pg_catalog.current_setting('forestring.system_semester_transition', true) = 'cron' then
      return query select null::uuid, 'master'::public.user_role, true;
      return;
    end if;
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_uid);

  select p.role into v_role
  from public.profiles p
  where p.id = v_uid and p.is_active = true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STAFF_REQUIRED';
  end if;

  return query select v_uid, v_role, false;
end;
$$;

revoke all on function private.require_semester_automation_actor() from public, anon, authenticated, service_role;

create or replace function private.semester_automation_run_date()
returns date
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_override text;
begin
  if session_user = 'postgres'
     and pg_catalog.current_setting('forestring.system_semester_transition', true) = 'cron' then
    v_override := nullif(pg_catalog.current_setting('forestring.system_semester_run_date', true), '');
    if v_override is not null then
      return v_override::date;
    end if;
  end if;

  return (pg_catalog.now() at time zone 'Asia/Seoul')::date;
end;
$$;

revoke all on function private.semester_automation_run_date() from public, anon, authenticated, service_role;

create or replace function public.materialize_flex_base_rights(p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_is_system boolean;
  v_plan public.student_semester_plans%rowtype;
  v_student_branch_id uuid;
  v_student_active boolean;
  v_student_status public.student_status;
  v_inserted_count integer;
  v_total_count integer;
  v_invalid_count integer;
begin
  select a.actor_id, a.actor_role, a.is_system
  into v_actor_id, v_actor_role, v_is_system
  from private.require_semester_automation_actor() a;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.id = p_plan_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_PLAN_NOT_FOUND';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_plan.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_plan.student_type_snapshot <> 'flex'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_PLAN_REQUIRED';
  end if;

  if v_plan.status <> 'active'::public.student_semester_plan_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_SEMESTER_PLAN_REQUIRED';
  end if;

  if v_plan.flex_base_right_count is null or v_plan.flex_duration_minutes is null then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';
  end if;

  select p.branch_id, p.is_active, s.status
  into v_student_branch_id, v_student_active, v_student_status
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = v_plan.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if not v_student_active or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_branch_id is distinct from v_plan.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_PLAN_BRANCH_MISMATCH';
  end if;

  select count(*)::integer into v_invalid_count
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin
    and (
      r.branch_id <> v_plan.branch_id
      or r.usable_semester_id <> v_plan.semester_id
      or r.duration_minutes <> v_plan.flex_duration_minutes
      or r.sequence_no > v_plan.flex_base_right_count
    );

  if v_invalid_count > 0 then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_RIGHTS_PLAN_MISMATCH';
  end if;

  insert into public.lesson_rights (
    student_id, branch_id, source_semester_id, usable_semester_id,
    schedule_slot_id, source_right_id, origin, sequence_no,
    duration_minutes, status, carryover_count, created_by
  )
  select
    v_plan.student_id, v_plan.branch_id, v_plan.semester_id, v_plan.semester_id,
    null, null, 'flex_base'::public.lesson_right_origin, sequence_no,
    v_plan.flex_duration_minutes, 'available'::public.lesson_right_status, 0, v_actor_id
  from generate_series(1, v_plan.flex_base_right_count) as sequence_no
  on conflict do nothing;

  get diagnostics v_inserted_count = row_count;

  select count(*)::integer into v_total_count
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin;

  if v_total_count <> v_plan.flex_base_right_count then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_RIGHT_COUNT_MISMATCH';
  end if;

  return jsonb_build_object(
    'planId', v_plan.id,
    'studentId', v_plan.student_id,
    'semesterId', v_plan.semester_id,
    'branchId', v_plan.branch_id,
    'baseRightCount', v_plan.flex_base_right_count,
    'durationMinutes', v_plan.flex_duration_minutes,
    'insertedCount', v_inserted_count,
    'totalCount', v_total_count
  );
end;
$$;

create or replace function public.activate_student_semester_plan(p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_is_system boolean;
  v_plan public.student_semester_plans%rowtype;
  v_student_branch_id uuid;
  v_student_profile_active boolean;
  v_student_status public.student_status;
  v_semester_start date;
  v_semester_end date;
  v_has_four_teaching_weeks boolean;
  v_slot record;
  v_candidate record;
  v_slot_count integer := 0;
  v_candidate_count integer := 0;
  v_expected_right_count integer := 0;
  v_existing_right_count integer := 0;
  v_existing_lesson_count integer := 0;
  v_created_right_count integer := 0;
  v_created_lesson_count integer := 0;
  v_right_id uuid;
  v_flex_result jsonb;
  v_plan_was_activated boolean := false;
begin
  select a.actor_id, a.actor_role, a.is_system
  into v_actor_id, v_actor_role, v_is_system
  from private.require_semester_automation_actor() a;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.id = p_plan_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_PLAN_NOT_FOUND';
  end if;

  if v_plan.status = 'completed'::public.student_semester_plan_status then
    raise exception using errcode='P0001', message='FORESTRING_COMPLETED_PLAN_IMMUTABLE';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_plan.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.branch_id, p.is_active, s.status
  into v_student_branch_id, v_student_profile_active, v_student_status
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = v_plan.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if not v_student_profile_active or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_branch_id is distinct from v_plan.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_PLAN_BRANCH_MISMATCH';
  end if;

  select e.starts_on, e.ends_on
  into v_semester_start, v_semester_end
  from private.get_effective_semester_bounds(v_plan.branch_id, v_plan.semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  select s.has_four_teaching_weeks
  into v_has_four_teaching_weeks
  from private.get_semester_week_summary(v_plan.branch_id, v_plan.semester_id) s;

  if not coalesce(v_has_four_teaching_weeks, false) then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS';
  end if;

  if v_plan.student_type_snapshot = 'flex'::public.student_type then
    if v_plan.flex_base_right_count is null or v_plan.flex_duration_minutes is null then
      raise exception using errcode='P0001', message='FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';
    end if;

    if v_plan.status = 'planned'::public.student_semester_plan_status then
      update public.student_semester_plans
      set status='active'::public.student_semester_plan_status,
          updated_by=v_actor_id
      where id=v_plan.id;
      v_plan_was_activated := true;
    end if;

    v_flex_result := public.materialize_flex_base_rights(v_plan.id);

    if v_plan_was_activated then
      insert into public.audit_events (
        subject_profile_id, branch_id, semester_id, event_type,
        effective_on, actor_id, details
      ) values (
        v_plan.student_id, v_plan.branch_id, v_plan.semester_id,
        'SEMESTER_PLAN_ACTIVATED', v_semester_start, v_actor_id,
        jsonb_build_object(
          'planId', v_plan.id,
          'studentType', 'flex',
          'baseRightCount', v_plan.flex_base_right_count,
          'durationMinutes', v_plan.flex_duration_minutes,
          'executionSource', case when v_is_system then 'system_cron' else 'staff' end
        )
      );
    end if;

    return jsonb_build_object(
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'studentType', 'flex',
      'changed', v_plan_was_activated,
      'materialization', v_flex_result
    );
  end if;

  if v_plan.student_type_snapshot <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_UNKNOWN_STUDENT_TYPE';
  end if;

  select count(*)::integer into v_slot_count
  from public.regular_schedule_slots rs
  where rs.student_id = v_plan.student_id
    and rs.branch_id = v_plan.branch_id
    and rs.starts_on <= v_semester_end
    and (rs.ends_on is null or rs.ends_on >= v_semester_start);

  if v_slot_count = 0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_PLAN_REQUIRES_SCHEDULE_SLOT';
  end if;

  v_expected_right_count := v_slot_count * 4;

  if v_plan.status = 'active'::public.student_semester_plan_status then
    select count(*)::integer into v_existing_right_count
    from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    select count(*)::integer into v_existing_lesson_count
    from public.lesson_rights r
    join public.lessons l on l.lesson_right_id=r.id
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    if v_existing_right_count <> v_expected_right_count
       or v_existing_lesson_count <> v_expected_right_count then
      raise exception using errcode='P0001', message='FORESTRING_ACTIVE_PLAN_MATERIALIZATION_INCOMPLETE';
    end if;

    return jsonb_build_object(
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'studentType', 'regular',
      'changed', false,
      'slotCount', v_slot_count,
      'rightCount', v_existing_right_count,
      'lessonCount', v_existing_lesson_count
    );
  end if;

  if exists (
    select 1 from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin
  ) then
    raise exception using errcode='P0001', message='FORESTRING_PLANNED_REGULAR_PLAN_ALREADY_HAS_RIGHTS';
  end if;

  for v_slot in
    select rs.id, rs.student_id, rs.branch_id, rs.starts_on, rs.ends_on
    from public.regular_schedule_slots rs
    where rs.student_id=v_plan.student_id
      and rs.branch_id=v_plan.branch_id
      and rs.starts_on <= v_semester_end
      and (rs.ends_on is null or rs.ends_on >= v_semester_start)
    order by rs.starts_on, rs.id
  loop
    select count(*)::integer into v_candidate_count
    from (
      with teaching_dates as (
        select d::date as lesson_date
        from generate_series(v_semester_start::timestamp, v_semester_end::timestamp, interval '1 day') d
        where not exists (
          select 1 from public.closure_periods cp
          where cp.branch_id=v_plan.branch_id
            and cp.semester_id=v_plan.semester_id
            and cp.closure_kind='instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      )
      select td.lesson_date, ls.id as series_id
      from teaching_dates td
      join public.lesson_series ls
        on ls.schedule_slot_id=v_slot.id
       and ls.student_id=v_plan.student_id
       and ls.branch_id=v_plan.branch_id
       and td.lesson_date >= ls.effective_from
       and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
       and extract(isodow from td.lesson_date)::integer=ls.weekday
      where td.lesson_date >= v_slot.starts_on
        and (v_slot.ends_on is null or td.lesson_date <= v_slot.ends_on)
    ) candidate_rows;

    if v_candidate_count <> 4 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES',
        detail='schedule_slot_id='||v_slot.id::text||', candidate_count='||v_candidate_count::text;
    end if;

    for v_candidate in
      with teaching_dates as (
        select d::date as lesson_date
        from generate_series(v_semester_start::timestamp, v_semester_end::timestamp, interval '1 day') d
        where not exists (
          select 1 from public.closure_periods cp
          where cp.branch_id=v_plan.branch_id
            and cp.semester_id=v_plan.semester_id
            and cp.closure_kind='instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      ), raw_candidates as (
        select td.lesson_date, ls.id as series_id, ls.teacher_id,
               ls.weekday, ls.start_time, ls.duration_minutes,
               (td.lesson_date + ls.start_time) at time zone 'Asia/Seoul' as starts_at
        from teaching_dates td
        join public.lesson_series ls
          on ls.schedule_slot_id=v_slot.id
         and ls.student_id=v_plan.student_id
         and ls.branch_id=v_plan.branch_id
         and td.lesson_date >= ls.effective_from
         and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
         and extract(isodow from td.lesson_date)::integer=ls.weekday
        where td.lesson_date >= v_slot.starts_on
          and (v_slot.ends_on is null or td.lesson_date <= v_slot.ends_on)
      )
      select row_number() over(order by rc.starts_at, rc.series_id)::integer as sequence_no,
             rc.lesson_date, rc.series_id, rc.teacher_id, rc.weekday,
             rc.start_time, rc.duration_minutes, rc.starts_at,
             rc.starts_at + pg_catalog.make_interval(mins=>rc.duration_minutes) as ends_at
      from raw_candidates rc
      order by rc.starts_at, rc.series_id
    loop
      if v_candidate.duration_minutes <= 0
         or mod(v_candidate.duration_minutes,15) <> 0 then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SERIES_INVALID_DURATION';
      end if;

      if exists (
        select 1 from public.closure_periods cp
        where cp.branch_id=v_plan.branch_id
          and cp.semester_id=v_plan.semester_id
          and cp.closure_kind='ordinary'::public.closure_kind
          and v_candidate.lesson_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE';
      end if;

      if not exists (
        select 1 from public.teacher_work_hours wh
        where wh.teacher_id=v_candidate.teacher_id
          and wh.weekday=v_candidate.weekday
          and wh.start_time <= v_candidate.start_time
          and wh.end_time >= (v_candidate.ends_at at time zone 'Asia/Seoul')::time
      ) then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',
          detail='schedule_slot_id='||v_slot.id::text||', date='||v_candidate.lesson_date::text;
      end if;

      if exists (
        select 1 from public.blocked_periods bp
        where bp.teacher_id=v_candidate.teacher_id
          and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_candidate.starts_at,v_candidate.ends_at,'[)')
      ) then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_BLOCKED',
          detail='schedule_slot_id='||v_slot.id::text||', date='||v_candidate.lesson_date::text;
      end if;

      insert into public.lesson_rights (
        student_id, branch_id, source_semester_id, usable_semester_id,
        schedule_slot_id, source_right_id, origin, sequence_no,
        duration_minutes, status, carryover_count, created_by, reserved_at
      ) values (
        v_plan.student_id, v_plan.branch_id, v_plan.semester_id, v_plan.semester_id,
        v_slot.id, null, 'regular_base'::public.lesson_right_origin, v_candidate.sequence_no,
        v_candidate.duration_minutes, 'reserved'::public.lesson_right_status, 0, v_actor_id, pg_catalog.now()
      ) returning id into v_right_id;

      v_created_right_count := v_created_right_count + 1;

      begin
        insert into public.lessons (
          series_id, student_id, teacher_id, occurrence_at, starts_at,
          duration_minutes, lesson_type, status, lesson_right_id
        ) values (
          v_candidate.series_id, v_plan.student_id, v_candidate.teacher_id,
          v_candidate.starts_at, v_candidate.starts_at, v_candidate.duration_minutes,
          'regular'::public.lesson_type, 'scheduled'::public.lesson_status, v_right_id
        );
      exception when exclusion_violation then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT',
          detail='schedule_slot_id='||v_slot.id::text||', starts_at='||v_candidate.starts_at::text;
      end;

      v_created_lesson_count := v_created_lesson_count + 1;
    end loop;
  end loop;

  if v_created_right_count <> v_expected_right_count
     or v_created_lesson_count <> v_expected_right_count then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_COUNT_MISMATCH';
  end if;

  update public.student_semester_plans
  set status='active'::public.student_semester_plan_status,
      updated_by=v_actor_id
  where id=v_plan.id;

  insert into public.audit_events (
    subject_profile_id, branch_id, semester_id, event_type,
    effective_on, actor_id, details
  ) values (
    v_plan.student_id, v_plan.branch_id, v_plan.semester_id,
    'SEMESTER_PLAN_ACTIVATED', v_semester_start, v_actor_id,
    jsonb_build_object(
      'planId', v_plan.id,
      'studentType', 'regular',
      'slotCount', v_slot_count,
      'rightCount', v_created_right_count,
      'lessonCount', v_created_lesson_count,
      'executionSource', case when v_is_system then 'system_cron' else 'staff' end
    )
  );

  return jsonb_build_object(
    'planId', v_plan.id,
    'studentId', v_plan.student_id,
    'studentType', 'regular',
    'changed', true,
    'slotCount', v_slot_count,
    'rightCount', v_created_right_count,
    'lessonCount', v_created_lesson_count
  );
end;
$$;

create or replace function public.finalize_student_semester_rights(
  p_source_plan_id uuid,
  p_target_plan_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_is_system boolean;
  v_source_plan public.student_semester_plans%rowtype;
  v_target_plan public.student_semester_plans%rowtype;
  v_source_start date;
  v_source_end date;
  v_target_start date;
  v_target_end date;
  v_boundary_date date;
  v_boundary_at timestamptz;
  v_run_date date;
  v_carryover_cap integer := 0;
  v_consumed_count integer := 0;
  v_carryover_count integer := 0;
  v_expired_count integer := 0;
  v_existing_carryovers integer := 0;
  v_candidate record;
begin
  select a.actor_id, a.actor_role, a.is_system
  into v_actor_id, v_actor_role, v_is_system
  from private.require_semester_automation_actor() a;

  v_run_date := private.semester_automation_run_date();

  select * into v_source_plan
  from public.student_semester_plans sp
  where sp.id=p_source_plan_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_PLAN_NOT_FOUND';
  end if;

  if v_actor_role='manager'::public.user_role
     and not private.manager_has_branch(v_source_plan.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select e.starts_on,e.ends_on into v_source_start,v_source_end
  from private.get_effective_semester_bounds(v_source_plan.branch_id,v_source_plan.semester_id) e;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_NOT_FOUND';
  end if;

  if p_target_plan_id is not null then
    select * into v_target_plan
    from public.student_semester_plans sp
    where sp.id=p_target_plan_id
    for update;

    if not found then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
    end if;

    if v_target_plan.student_id <> v_source_plan.student_id then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_PLAN_STUDENT_MISMATCH';
    end if;

    if v_target_plan.branch_id <> v_source_plan.branch_id then
      raise exception using errcode='P0001', message='FORESTRING_CARRYOVER_BRANCH_TRANSFER_REQUIRES_DEDICATED_FLOW';
    end if;

    if v_actor_role='manager'::public.user_role
       and not private.manager_has_branch(v_target_plan.branch_id) then
      raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
    end if;

    if v_target_plan.status='completed'::public.student_semester_plan_status then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_ALREADY_COMPLETED';
    end if;

    select e.starts_on,e.ends_on into v_target_start,v_target_end
    from private.get_effective_semester_bounds(v_target_plan.branch_id,v_target_plan.semester_id) e;
    if not found then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_FOUND';
    end if;

    if v_target_start <> v_source_end + 1 then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_CONSECUTIVE';
    end if;

    v_boundary_date := v_target_start;
  else
    v_boundary_date := v_source_end + 1;
  end if;

  if v_run_date < v_boundary_date then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_READY_FOR_FINALIZATION';
  end if;

  v_boundary_at := (v_boundary_date::timestamp at time zone 'Asia/Seoul');

  if v_source_plan.status='completed'::public.student_semester_plan_status then
    if p_target_plan_id is not null then
      select count(*)::integer into v_existing_carryovers
      from public.lesson_rights r
      where r.student_id=v_source_plan.student_id
        and r.origin='carryover'::public.lesson_right_origin
        and r.usable_semester_id=v_target_plan.semester_id
        and exists (
          select 1 from public.lesson_rights sr
          where sr.id=r.source_right_id
            and sr.source_semester_id=v_source_plan.semester_id
        );
    end if;

    return jsonb_build_object(
      'changed',false,'sourcePlanId',v_source_plan.id,'targetPlanId',p_target_plan_id,
      'carryoverCreated',v_existing_carryovers,'status','completed'
    );
  end if;

  if v_source_plan.status <> 'active'::public.student_semester_plan_status then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_PLAN_NOT_ACTIVE';
  end if;

  if p_target_plan_id is null then
    v_carryover_cap := 0;
  elsif v_source_plan.student_type_snapshot='regular'::public.student_type then
    v_carryover_cap := 1;
  elsif v_source_plan.student_type_snapshot='flex'::public.student_type then
    if v_source_plan.flex_base_right_count is null then
      raise exception using errcode='P0001', message='FORESTRING_FLEX_SEMESTER_PLAN_CONFIGURATION_REQUIRED';
    end if;
    v_carryover_cap := floor(v_source_plan.flex_base_right_count::numeric/4)::integer;
  else
    raise exception using errcode='P0001', message='FORESTRING_UNSUPPORTED_STUDENT_TYPE';
  end if;

  if exists (
    select 1
    from public.lesson_rights r
    join public.lessons l on l.lesson_right_id=r.id
    where r.student_id=v_source_plan.student_id
      and r.source_semester_id=v_source_plan.semester_id
      and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
      and r.status='reserved'::public.lesson_right_status
      and l.status='scheduled'::public.lesson_status
      and l.starts_at >= v_boundary_at
  ) then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_HAS_FUTURE_RESERVED_LESSON';
  end if;

  if exists (
    select 1 from public.lesson_rights r
    where r.student_id=v_source_plan.student_id
      and r.source_semester_id=v_source_plan.semester_id
      and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
      and r.status='reserved'::public.lesson_right_status
      and not exists (
        select 1 from public.lessons l
        where l.lesson_right_id=r.id
          and l.status='scheduled'::public.lesson_status
          and l.starts_at < v_boundary_at
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_RIGHT_RESERVATION_UNRESOLVED';
  end if;

  update public.lesson_rights r
  set status='consumed'::public.lesson_right_status,
      consumed_at=coalesce(r.consumed_at,pg_catalog.now())
  from public.lessons l
  where l.lesson_right_id=r.id
    and r.student_id=v_source_plan.student_id
    and r.source_semester_id=v_source_plan.semester_id
    and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
    and r.status='reserved'::public.lesson_right_status
    and l.status='scheduled'::public.lesson_status
    and l.starts_at < v_boundary_at;
  get diagnostics v_consumed_count=row_count;

  if p_target_plan_id is not null and v_carryover_cap > 0 then
    for v_candidate in
      select r.id,r.student_id,r.source_semester_id,r.sequence_no,r.duration_minutes,
             cancellation.first_canceled_at
      from public.lesson_rights r
      left join lateral (
        select min(e.canceled_at) as first_canceled_at
        from public.lesson_cancellation_events e
        where e.lesson_right_id=r.id
      ) cancellation on true
      where r.student_id=v_source_plan.student_id
        and r.source_semester_id=v_source_plan.semester_id
        and r.status='available'::public.lesson_right_status
        and r.carryover_count=0
        and (
          (v_source_plan.student_type_snapshot='regular'::public.student_type and r.origin='regular_base'::public.lesson_right_origin)
          or
          (v_source_plan.student_type_snapshot='flex'::public.student_type and r.origin='flex_base'::public.lesson_right_origin)
        )
        and not exists (
          select 1 from public.lesson_rights existing
          where existing.source_right_id=r.id
            and existing.origin='carryover'::public.lesson_right_origin
        )
      order by (cancellation.first_canceled_at is null) asc,
               cancellation.first_canceled_at asc nulls last,
               r.sequence_no asc,r.id asc
      limit v_carryover_cap
    loop
      insert into public.lesson_rights (
        student_id,branch_id,source_semester_id,usable_semester_id,
        schedule_slot_id,source_right_id,origin,sequence_no,duration_minutes,
        status,carryover_count,created_by
      ) values (
        v_candidate.student_id,v_target_plan.branch_id,v_candidate.source_semester_id,
        v_target_plan.semester_id,null,v_candidate.id,'carryover'::public.lesson_right_origin,
        v_candidate.sequence_no,v_candidate.duration_minutes,'available'::public.lesson_right_status,
        1,v_actor_id
      );
      v_carryover_count := v_carryover_count + 1;
    end loop;
  end if;

  update public.lesson_rights r
  set status='expired'::public.lesson_right_status,
      expired_at=coalesce(r.expired_at,pg_catalog.now())
  where r.student_id=v_source_plan.student_id
    and r.source_semester_id=v_source_plan.semester_id
    and r.status='available'::public.lesson_right_status
    and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin);
  get diagnostics v_expired_count=row_count;

  update public.student_semester_plans
  set status='completed'::public.student_semester_plan_status,
      updated_by=v_actor_id
  where id=v_source_plan.id;

  insert into public.audit_events (
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    v_source_plan.student_id,v_source_plan.branch_id,v_source_plan.semester_id,
    'STUDENT_SEMESTER_RIGHTS_FINALIZED',v_boundary_date,v_actor_id,
    jsonb_build_object(
      'sourcePlanId',v_source_plan.id,
      'sourceSemesterId',v_source_plan.semester_id,
      'targetPlanId',p_target_plan_id,
      'targetSemesterId',case when p_target_plan_id is null then null else v_target_plan.semester_id end,
      'studentType',v_source_plan.student_type_snapshot,
      'carryoverCap',v_carryover_cap,
      'carryoverCreated',v_carryover_count,
      'consumedReservedRights',v_consumed_count,
      'expiredAvailableRights',v_expired_count,
      'executionSource',case when v_is_system then 'system_cron' else 'staff' end
    )
  );

  return jsonb_build_object(
    'changed',true,'sourcePlanId',v_source_plan.id,'targetPlanId',p_target_plan_id,
    'studentType',v_source_plan.student_type_snapshot,'carryoverCap',v_carryover_cap,
    'carryoverCreated',v_carryover_count,'consumedReservedRights',v_consumed_count,
    'expiredAvailableRights',v_expired_count,'status','completed'
  );
end;
$$;

create or replace function public.transition_student_semester(
  p_source_plan_id uuid,
  p_target_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_is_system boolean;
  v_source_plan public.student_semester_plans%rowtype;
  v_target_plan public.student_semester_plans%rowtype;
  v_current_student_type public.student_type;
  v_student_status public.student_status;
  v_student_branch_id uuid;
  v_source_start date;
  v_source_end date;
  v_target_start date;
  v_target_end date;
  v_run_date date;
  v_finalization_result jsonb;
  v_activation_result jsonb;
  v_type_changed boolean := false;
  v_closed_slot_count integer := 0;
  v_closed_series_count integer := 0;
  v_changed boolean := false;
begin
  select a.actor_id,a.actor_role,a.is_system
  into v_actor_id,v_actor_role,v_is_system
  from private.require_semester_automation_actor() a;

  if p_source_plan_id is null or p_target_plan_id is null then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_TRANSITION_PLAN_REQUIRED';
  end if;
  if p_source_plan_id=p_target_plan_id then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_TRANSITION_SAME_PLAN';
  end if;

  select * into v_source_plan
  from public.student_semester_plans sp where sp.id=p_source_plan_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_PLAN_NOT_FOUND';
  end if;

  select * into v_target_plan
  from public.student_semester_plans sp where sp.id=p_target_plan_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
  end if;

  if v_source_plan.student_id <> v_target_plan.student_id then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_TRANSITION_STUDENT_MISMATCH';
  end if;
  if v_source_plan.branch_id <> v_target_plan.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_TRANSFER_REQUIRES_DEDICATED_FLOW';
  end if;
  if v_target_plan.status='completed'::public.student_semester_plan_status then
    raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_ALREADY_COMPLETED';
  end if;

  select s.student_type,s.status,p.branch_id
  into v_current_student_type,v_student_status,v_student_branch_id
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=v_source_plan.student_id and p.is_active=true
  for update of s;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;
  if v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_INACTIVE';
  end if;
  if v_student_branch_id is distinct from v_source_plan.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_MISMATCH';
  end if;
  if v_actor_role='manager'::public.user_role
     and not private.manager_has_branch(v_source_plan.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select e.starts_on,e.ends_on into v_source_start,v_source_end
  from private.get_effective_semester_bounds(v_source_plan.branch_id,v_source_plan.semester_id) e;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SOURCE_SEMESTER_NOT_FOUND';
  end if;

  select e.starts_on,e.ends_on into v_target_start,v_target_end
  from private.get_effective_semester_bounds(v_target_plan.branch_id,v_target_plan.semester_id) e;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_FOUND';
  end if;

  if v_target_start <> v_source_end + 1 then
    raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_CONSECUTIVE';
  end if;

  v_run_date := private.semester_automation_run_date();
  if v_run_date < v_target_start then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_TRANSITION_NOT_READY';
  end if;

  v_finalization_result := public.finalize_student_semester_rights(v_source_plan.id,v_target_plan.id);
  if coalesce((v_finalization_result->>'changed')::boolean,false) then
    v_changed := true;
  end if;

  if v_source_plan.student_type_snapshot='regular'::public.student_type
     and v_target_plan.student_type_snapshot='flex'::public.student_type then
    update public.lesson_series ls
    set effective_until=v_source_end
    where ls.student_id=v_source_plan.student_id
      and ls.branch_id=v_source_plan.branch_id
      and ls.schedule_slot_id in (
        select rs.id from public.regular_schedule_slots rs
        where rs.student_id=v_source_plan.student_id
          and rs.branch_id=v_source_plan.branch_id
          and rs.starts_on <= v_source_end
          and (rs.ends_on is null or rs.ends_on > v_source_end)
      )
      and ls.effective_from <= v_source_end
      and (ls.effective_until is null or ls.effective_until > v_source_end);
    get diagnostics v_closed_series_count=row_count;

    update public.regular_schedule_slots rs
    set ends_on=v_source_end
    where rs.student_id=v_source_plan.student_id
      and rs.branch_id=v_source_plan.branch_id
      and rs.starts_on <= v_source_end
      and (rs.ends_on is null or rs.ends_on > v_source_end);
    get diagnostics v_closed_slot_count=row_count;

    if v_closed_series_count>0 or v_closed_slot_count>0 then v_changed:=true; end if;
  end if;

  if v_current_student_type <> v_target_plan.student_type_snapshot then
    update public.students set student_type=v_target_plan.student_type_snapshot
    where id=v_source_plan.student_id;
    v_type_changed:=true;
    v_changed:=true;
  end if;

  v_activation_result := public.activate_student_semester_plan(v_target_plan.id);
  if coalesce((v_activation_result->>'changed')::boolean,false) then
    v_changed:=true;
  end if;

  if v_changed then
    insert into public.audit_events (
      subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
    ) values (
      v_source_plan.student_id,v_source_plan.branch_id,v_target_plan.semester_id,
      'STUDENT_SEMESTER_TRANSITIONED',v_target_start,v_actor_id,
      jsonb_build_object(
        'sourcePlanId',v_source_plan.id,'targetPlanId',v_target_plan.id,
        'sourceSemesterId',v_source_plan.semester_id,'targetSemesterId',v_target_plan.semester_id,
        'previousStudentType',v_source_plan.student_type_snapshot,
        'targetStudentType',v_target_plan.student_type_snapshot,
        'studentTypeChanged',v_type_changed,
        'closedRegularSlotCount',v_closed_slot_count,
        'closedRegularSeriesCount',v_closed_series_count,
        'finalization',v_finalization_result,'activation',v_activation_result,
        'executionSource',case when v_is_system then 'system_cron' else 'staff' end
      )
    );
  end if;

  return jsonb_build_object(
    'changed',v_changed,'studentId',v_source_plan.student_id,
    'sourcePlanId',v_source_plan.id,'targetPlanId',v_target_plan.id,
    'effectiveOn',v_target_start,'previousStudentType',v_source_plan.student_type_snapshot,
    'studentType',v_target_plan.student_type_snapshot,'studentTypeChanged',v_type_changed,
    'closedRegularSlotCount',v_closed_slot_count,'closedRegularSeriesCount',v_closed_series_count,
    'finalization',v_finalization_result,'activation',v_activation_result
  );
end;
$$;

create or replace function private.ensure_semester_plan_materialized(
  p_student_id uuid,
  p_semester_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor record;
  v_student_type public.student_type;
  v_student_status public.student_status;
  v_branch_id uuid;
  v_active boolean;
  v_withdrawal_date date;
  v_semester_start date;
  v_semester_end date;
  v_plan public.student_semester_plans%rowtype;
  v_plan_id uuid;
  v_plan_created boolean := false;
  v_flex_count integer;
  v_flex_duration integer;
  v_activation jsonb;
begin
  select * into v_actor from private.require_semester_automation_actor();
  if not v_actor.is_system then
    raise exception using errcode='42501', message='FORESTRING_SYSTEM_SEMESTER_AUTOMATION_REQUIRED';
  end if;

  select s.student_type,s.status,p.branch_id,p.is_active,s.withdrawal_date
  into v_student_type,v_student_status,v_branch_id,v_active,v_withdrawal_date
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id;

  if not found or not v_active or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  select e.starts_on,e.ends_on into v_semester_start,v_semester_end
  from private.get_effective_semester_bounds(v_branch_id,p_semester_id) e;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if v_withdrawal_date is not null and v_withdrawal_date <= v_semester_end then
    return jsonb_build_object(
      'studentId',p_student_id,'semesterId',p_semester_id,
      'changed',false,'skipped',true,'reason','withdrawal_within_semester'
    );
  end if;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.student_id=p_student_id and sp.semester_id=p_semester_id
  for update;

  if found then
    v_plan_id := v_plan.id;
  else
    if v_student_type='regular'::public.student_type then
      insert into public.student_semester_plans (
        student_id,semester_id,branch_id,student_type_snapshot,
        flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
      ) values (
        p_student_id,p_semester_id,v_branch_id,'regular'::public.student_type,
        null,null,'planned'::public.student_semester_plan_status,null,null
      ) returning id into v_plan_id;
    elsif v_student_type='flex'::public.student_type then
      select sp.flex_base_right_count,sp.flex_duration_minutes
      into v_flex_count,v_flex_duration
      from public.student_semester_plans sp
      join public.semesters sem on sem.id=sp.semester_id
      where sp.student_id=p_student_id
        and sp.student_type_snapshot='flex'::public.student_type
        and sp.flex_base_right_count is not null
        and sp.flex_duration_minutes is not null
        and sem.starts_on < (select starts_on from public.semesters where id=p_semester_id)
      order by sem.starts_on desc
      limit 1;

      if v_flex_count is null or v_flex_duration is null then
        raise exception using errcode='P0001', message='FORESTRING_FLEX_SEMESTER_PLAN_CONFIGURATION_REQUIRED';
      end if;

      insert into public.student_semester_plans (
        student_id,semester_id,branch_id,student_type_snapshot,
        flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
      ) values (
        p_student_id,p_semester_id,v_branch_id,'flex'::public.student_type,
        v_flex_count,v_flex_duration,'planned'::public.student_semester_plan_status,null,null
      ) returning id into v_plan_id;
    else
      raise exception using errcode='P0001', message='FORESTRING_UNSUPPORTED_STUDENT_TYPE';
    end if;
    v_plan_created := true;
  end if;

  v_activation := public.activate_student_semester_plan(v_plan_id);

  return jsonb_build_object(
    'studentId',p_student_id,'semesterId',p_semester_id,'planId',v_plan_id,
    'planCreated',v_plan_created,
    'changed',v_plan_created or coalesce((v_activation->>'changed')::boolean,false),
    'skipped',false,'activation',v_activation
  );
end;
$$;

revoke all on function private.ensure_semester_plan_materialized(uuid,uuid) from public, anon, authenticated, service_role;

create or replace function private.run_due_semester_automation(p_run_date date default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_run_date date;
  v_source record;
  v_student record;
  v_target_semester_id uuid;
  v_target_plan_id uuid;
  v_current_semester_id uuid;
  v_current_end date;
  v_next_semester_id uuid;
  v_next_end date;
  v_result jsonb;
  v_ensure jsonb;
  v_attempted_transition integer := 0;
  v_transitioned integer := 0;
  v_transition_failed integer := 0;
  v_carryover_created integer := 0;
  v_future_attempted integer := 0;
  v_future_materialized integer := 0;
  v_future_ready integer := 0;
  v_future_skipped_withdrawal integer := 0;
  v_future_missing_semester integer := 0;
  v_future_failed integer := 0;
  v_error_state text;
  v_error_message text;
begin
  if session_user <> 'postgres' then
    raise exception using errcode='42501', message='FORESTRING_SYSTEM_SEMESTER_AUTOMATION_FORBIDDEN';
  end if;

  v_run_date := coalesce(p_run_date,(pg_catalog.now() at time zone 'Asia/Seoul')::date);

  perform pg_catalog.set_config('forestring.system_semester_transition','cron',true);
  perform pg_catalog.set_config('forestring.system_semester_run_date',v_run_date::text,true);

  for v_source in
    select sp.id as source_plan_id,sp.student_id,sp.branch_id,s.withdrawal_date
    from public.student_semester_plans sp
    join public.students s on s.id=sp.student_id
    join public.profiles p on p.id=sp.student_id
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) e
    where sp.status='active'::public.student_semester_plan_status
      and e.ends_on=v_run_date-1
      and s.status='active'::public.student_status
      and p.is_active=true
      and (s.withdrawal_date is null or s.withdrawal_date > v_run_date)
    order by sp.student_id
  loop
    v_attempted_transition := v_attempted_transition + 1;
    begin
      select sem.id into v_target_semester_id
      from public.semesters sem
      cross join lateral private.get_effective_semester_bounds(v_source.branch_id,sem.id) e
      where e.starts_on=v_run_date
      order by sem.starts_on
      limit 1;

      if v_target_semester_id is null then
        raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_FOUND';
      end if;

      v_ensure := private.ensure_semester_plan_materialized(v_source.student_id,v_target_semester_id);

      select sp.id into v_target_plan_id
      from public.student_semester_plans sp
      where sp.student_id=v_source.student_id and sp.semester_id=v_target_semester_id;

      if v_target_plan_id is null then
        raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
      end if;

      v_result := public.transition_student_semester(v_source.source_plan_id,v_target_plan_id);
      v_transitioned := v_transitioned + 1;
      v_carryover_created := v_carryover_created + coalesce((v_result->'finalization'->>'carryoverCreated')::integer,0);
    exception when others then
      get stacked diagnostics v_error_state=returned_sqlstate,v_error_message=message_text;
      v_transition_failed := v_transition_failed + 1;
      insert into public.audit_events (
        subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
      ) values (
        v_source.student_id,v_source.branch_id,null,'STUDENT_SEMESTER_AUTO_FAILED',v_run_date,null,
        jsonb_build_object(
          'executionSource','system_cron','runDateKst',v_run_date,
          'sqlState',v_error_state,'message',v_error_message
        )
      );
      raise warning 'Automatic semester transition failed for student %: [%] %',v_source.student_id,v_error_state,v_error_message;
    end;
  end loop;

  for v_student in
    select s.id as student_id,p.branch_id,s.withdrawal_date
    from public.students s
    join public.profiles p on p.id=s.id
    where s.status='active'::public.student_status
      and p.is_active=true
      and (s.withdrawal_date is null or s.withdrawal_date > v_run_date)
    order by s.id
  loop
    begin
      v_current_semester_id := null;
      v_current_end := null;
      v_next_semester_id := null;
      v_next_end := null;

      select sem.id,e.ends_on
      into v_current_semester_id,v_current_end
      from public.semesters sem
      cross join lateral private.get_effective_semester_bounds(v_student.branch_id,sem.id) e
      where v_run_date between e.starts_on and e.ends_on
      order by e.starts_on desc
      limit 1;

      if v_current_semester_id is null then
        continue;
      end if;

      select sem.id,e.ends_on
      into v_next_semester_id,v_next_end
      from public.semesters sem
      cross join lateral private.get_effective_semester_bounds(v_student.branch_id,sem.id) e
      where e.starts_on=v_current_end+1
      order by e.starts_on
      limit 1;

      if v_next_semester_id is null then
        v_future_missing_semester := v_future_missing_semester + 1;
        continue;
      end if;

      if v_student.withdrawal_date is not null and v_student.withdrawal_date <= v_next_end then
        v_future_skipped_withdrawal := v_future_skipped_withdrawal + 1;
        continue;
      end if;

      v_future_attempted := v_future_attempted + 1;
      v_ensure := private.ensure_semester_plan_materialized(v_student.student_id,v_next_semester_id);

      if coalesce((v_ensure->>'skipped')::boolean,false) then
        v_future_skipped_withdrawal := v_future_skipped_withdrawal + 1;
      elsif coalesce((v_ensure->>'changed')::boolean,false) then
        v_future_materialized := v_future_materialized + 1;
      else
        v_future_ready := v_future_ready + 1;
      end if;
    exception when others then
      get stacked diagnostics v_error_state=returned_sqlstate,v_error_message=message_text;
      v_future_failed := v_future_failed + 1;
      insert into public.audit_events (
        subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
      ) values (
        v_student.student_id,v_student.branch_id,v_next_semester_id,
        'STUDENT_NEXT_SEMESTER_AUTO_FAILED',v_run_date,null,
        jsonb_build_object(
          'executionSource','system_cron','runDateKst',v_run_date,
          'sqlState',v_error_state,'message',v_error_message
        )
      );
      raise warning 'Automatic next-semester materialization failed for student %: [%] %',v_student.student_id,v_error_state,v_error_message;
    end;
  end loop;

  return jsonb_build_object(
    'runDateKst',v_run_date,
    'transitionAttemptedCount',v_attempted_transition,
    'transitionedCount',v_transitioned,
    'transitionFailedCount',v_transition_failed,
    'carryoverCreatedCount',v_carryover_created,
    'futureAttemptedCount',v_future_attempted,
    'futureMaterializedCount',v_future_materialized,
    'futureAlreadyReadyCount',v_future_ready,
    'futureSkippedWithdrawalCount',v_future_skipped_withdrawal,
    'futureMissingSemesterCount',v_future_missing_semester,
    'futureFailedCount',v_future_failed
  );
end;
$$;

revoke all on function private.run_due_semester_automation(date) from public, anon, authenticated, service_role;

select cron.schedule(
  'forestring-semester-automation',
  '15 15 * * *',
  $$select private.run_due_semester_automation();$$
);
