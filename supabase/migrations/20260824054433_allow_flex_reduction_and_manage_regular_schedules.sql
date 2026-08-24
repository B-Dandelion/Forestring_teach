-- ============================================================
-- Forestring v3
-- Flexible entitlement reduction + regular schedule add/end
-- ============================================================


-- ============================================================
-- 1. FLEX BASE RIGHT COUNT
--
-- A reduction revokes available rights instead of deleting
-- ledger rows. This preserves lessons and cancellation events.
-- Previously revoked rights are restored before new rows are
-- issued when the configured count increases again.
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

  v_active_right_count integer;
  v_invalid_right_count integer;
  v_available_revoke_count integer;
  v_counted_cancellation_count integer;
  v_change_count integer;
  v_max_sequence integer;

  v_inserted_count integer := 0;
  v_reactivated_count integer := 0;
  v_revoked_count integer := 0;
  v_inserted_right_ids jsonb := '[]'::jsonb;
  v_reactivated_right_ids jsonb := '[]'::jsonb;
  v_revoked_right_ids jsonb := '[]'::jsonb;
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
     or v_student_status <> 'active'::public.student_status then
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

  perform 1
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin
  order by r.sequence_no
  for update;

  select
    count(*) filter (
      where r.status <> 'revoked'::public.lesson_right_status
    )::integer,
    count(*) filter (
      where r.branch_id is distinct from v_plan.branch_id
         or r.usable_semester_id is distinct from v_plan.semester_id
         or r.duration_minutes is distinct from v_plan.flex_duration_minutes
         or r.sequence_no < 1
    )::integer,
    coalesce(max(r.sequence_no), 0)::integer
  into
    v_active_right_count,
    v_invalid_right_count,
    v_max_sequence
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin;

  if v_active_right_count <> v_old_base_right_count
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

  if p_new_base_right_count = v_old_base_right_count then
    return jsonb_build_object(
      'changed', false,
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'semesterId', v_plan.semester_id,
      'oldBaseRightCount', v_old_base_right_count,
      'newBaseRightCount', p_new_base_right_count,
      'insertedCount', 0,
      'reactivatedCount', 0,
      'removedCount', 0,
      'revokedCount', 0,
      'countedStudentCancellations', v_counted_cancellation_count,
      'newCancellationLimit', v_new_cancellation_limit,
      'remainingCancellations', greatest(
        v_new_cancellation_limit - v_counted_cancellation_count,
        0
      ),
      'newCarryoverCap', v_new_carryover_cap
    );
  end if;

  if p_new_base_right_count < v_old_base_right_count then
    v_change_count := v_old_base_right_count - p_new_base_right_count;

    select count(*)::integer
    into v_available_revoke_count
    from public.lesson_rights r
    where r.student_id = v_plan.student_id
      and r.source_semester_id = v_plan.semester_id
      and r.origin = 'flex_base'::public.lesson_right_origin
      and r.status = 'available'::public.lesson_right_status
      and not exists (
        select 1
        from public.lessons l
        where l.lesson_right_id = r.id
          and l.status = 'scheduled'::public.lesson_status
      )
      and not exists (
        select 1
        from public.lesson_rights carried
        where carried.source_right_id = r.id
      );

    if v_available_revoke_count < v_change_count then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_FLEX_RIGHT_COUNT_DECREASE_BLOCKED';
    end if;

    with candidates as (
      select r.id
      from public.lesson_rights r
      where r.student_id = v_plan.student_id
        and r.source_semester_id = v_plan.semester_id
        and r.origin = 'flex_base'::public.lesson_right_origin
        and r.status = 'available'::public.lesson_right_status
        and not exists (
          select 1
          from public.lessons l
          where l.lesson_right_id = r.id
            and l.status = 'scheduled'::public.lesson_status
        )
        and not exists (
          select 1
          from public.lesson_rights carried
          where carried.source_right_id = r.id
        )
      order by
        case
          when not exists (
            select 1 from public.lessons l
            where l.lesson_right_id = r.id
          ) and not exists (
            select 1 from public.lesson_cancellation_events e
            where e.lesson_right_id = r.id
          ) then 0
          when not exists (
            select 1 from public.lesson_cancellation_events e
            where e.lesson_right_id = r.id
              and e.origin = 'student'::public.lesson_cancellation_origin
          ) then 1
          else 2
        end,
        r.sequence_no desc,
        r.id
      limit v_change_count
      for update
    ), revoked as (
      update public.lesson_rights r
      set
        status = 'revoked'::public.lesson_right_status,
        reserved_at = null,
        revoked_at = coalesce(r.revoked_at, pg_catalog.now())
      from candidates c
      where r.id = c.id
      returning r.id
    )
    select
      count(*)::integer,
      coalesce(jsonb_agg(revoked.id), '[]'::jsonb)
    into v_revoked_count, v_revoked_right_ids
    from revoked;
  else
    v_change_count := p_new_base_right_count - v_old_base_right_count;

    with candidates as (
      select r.id
      from public.lesson_rights r
      where r.student_id = v_plan.student_id
        and r.source_semester_id = v_plan.semester_id
        and r.origin = 'flex_base'::public.lesson_right_origin
        and r.status = 'revoked'::public.lesson_right_status
        and not exists (
          select 1
          from public.lesson_rights carried
          where carried.source_right_id = r.id
        )
      order by r.sequence_no, r.id
      limit v_change_count
      for update
    ), reactivated as (
      update public.lesson_rights r
      set
        status = 'available'::public.lesson_right_status,
        revoked_at = null
      from candidates c
      where r.id = c.id
      returning r.id
    )
    select
      count(*)::integer,
      coalesce(jsonb_agg(reactivated.id), '[]'::jsonb)
    into v_reactivated_count, v_reactivated_right_ids
    from reactivated;

    v_change_count := v_change_count - v_reactivated_count;

    if v_change_count > 0 then
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
          v_max_sequence + generated.ordinal,
          v_plan.flex_duration_minutes,
          'available'::public.lesson_right_status,
          0,
          v_actor_id
        from generate_series(1, v_change_count) as generated(ordinal)
        returning id
      )
      select
        count(*)::integer,
        coalesce(jsonb_agg(inserted.id), '[]'::jsonb)
      into v_inserted_count, v_inserted_right_ids
      from inserted;
    end if;
  end if;

  update public.student_semester_plans
  set
    flex_base_right_count = p_new_base_right_count,
    updated_by = v_actor_id
  where id = v_plan.id;

  select count(*) filter (
    where r.status <> 'revoked'::public.lesson_right_status
  )::integer
  into v_active_right_count
  from public.lesson_rights r
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin;

  if v_active_right_count <> p_new_base_right_count then
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
      'reactivatedCount', v_reactivated_count,
      'revokedCount', v_revoked_count,
      'insertedRightIds', v_inserted_right_ids,
      'reactivatedRightIds', v_reactivated_right_ids,
      'revokedRightIds', v_revoked_right_ids,
      'countedStudentCancellations', v_counted_cancellation_count,
      'oldCancellationLimit', v_old_cancellation_limit,
      'newCancellationLimit', v_new_cancellation_limit,
      'remainingCancellations', greatest(
        v_new_cancellation_limit - v_counted_cancellation_count,
        0
      ),
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
    'reactivatedCount', v_reactivated_count,
    'removedCount', v_revoked_count,
    'revokedCount', v_revoked_count,
    'countedStudentCancellations', v_counted_cancellation_count,
    'oldCancellationLimit', v_old_cancellation_limit,
    'newCancellationLimit', v_new_cancellation_limit,
    'remainingCancellations', greatest(
      v_new_cancellation_limit - v_counted_cancellation_count,
      0
    ),
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
  'Atomically changes an active flex semester base-right count. Reductions revoke available rights while preserving lesson and cancellation history; increases restore revoked rights before issuing new rows. Already-counted cancellations are preserved and only reduce the remaining current-semester quota. Master or same-branch manager only.';


-- ============================================================
-- 2. ADD A REGULAR SCHEDULE FROM A SEMESTER BOUNDARY
-- ============================================================

create or replace function public.add_regular_schedule(
  p_student_id uuid,
  p_teacher_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_duration_minutes integer,
  p_effective_on date
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
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_student_branch_id uuid;
  v_student_active boolean;
  v_student_status public.student_status;
  v_student_type public.student_type;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_semester_id uuid;
  v_semester_end date;
  v_target_plan_type public.student_type;
  v_target_plan_status public.student_semester_plan_status;

  v_end_time time;
  v_slot_id uuid;
  v_series_id uuid;
begin
  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
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
      message = 'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_weekday not between 1 and 7 then
    raise exception using errcode = 'P0001', message = 'FORESTRING_INVALID_WEEKDAY';
  end if;

  if p_start_time is null
     or extract(second from p_start_time) <> 0
     or mod(extract(minute from p_start_time)::integer, 15) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_REGULAR_DURATION';
  end if;

  if extract(hour from p_start_time)::integer * 60
       + extract(minute from p_start_time)::integer
       + p_duration_minutes > 1440 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_LESSON_CROSSES_MIDNIGHT';
  end if;

  v_end_time := (
    p_start_time + pg_catalog.make_interval(mins => p_duration_minutes)
  )::time;

  select p.branch_id, p.is_active, s.status, s.student_type
  into v_student_branch_id, v_student_active, v_student_status, v_student_type
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true
     or v_student_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'regular'::public.student_type then
    raise exception using errcode = 'P0001', message = 'FORESTRING_REGULAR_STUDENT_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.branch_id, p.is_active, t.withdrawal_date
  into v_teacher_branch_id, v_teacher_active, v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id = t.id
  where t.id = p_teacher_id;

  if not found or v_teacher_active <> true then
    raise exception using errcode = 'P0001', message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using errcode = 'P0001', message = 'FORESTRING_BRANCH_MISMATCH';
  end if;

  select s.id, bounds.ends_on
  into v_semester_id, v_semester_end
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    v_student_branch_id,
    s.id
  ) bounds
  where bounds.starts_on = p_effective_on
  order by s.starts_on
  limit 1;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_ADD_REQUIRES_SEMESTER_START';
  end if;

  if v_teacher_withdrawal_date is not null
     and v_teacher_withdrawal_date <= v_semester_end then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if not exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = p_student_id
      and a.teacher_id = p_teacher_id
      and a.branch_id = v_student_branch_id
      and a.starts_on <= p_effective_on
      and (a.ends_on is null or a.ends_on >= v_semester_end)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH';
  end if;

  if not exists (
    select 1
    from public.teacher_work_hours wh
    where wh.teacher_id = p_teacher_id
      and wh.weekday = p_weekday
      and wh.start_time <= p_start_time
      and wh.end_time >= v_end_time
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS';
  end if;

  select sp.student_type_snapshot, sp.status
  into v_target_plan_type, v_target_plan_status
  from public.student_semester_plans sp
  where sp.student_id = p_student_id
    and sp.semester_id = v_semester_id
  for update;

  if found then
    if v_target_plan_type <> 'regular'::public.student_type then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_TARGET_SEMESTER_NOT_REGULAR';
    end if;

    if v_target_plan_status <> 'planned'::public.student_semester_plan_status then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_ADD_ACTIVE_SEMESTER_FORBIDDEN';
    end if;
  end if;

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    ends_on,
    created_by
  )
  values (
    p_student_id,
    v_student_branch_id,
    p_effective_on,
    null,
    v_actor_id
  )
  returning id into v_slot_id;

  begin
    insert into public.lesson_series (
      student_id,
      teacher_id,
      weekday,
      start_time,
      duration_minutes,
      effective_from,
      effective_until,
      branch_id,
      schedule_slot_id
    )
    values (
      p_student_id,
      p_teacher_id,
      p_weekday,
      p_start_time,
      p_duration_minutes,
      p_effective_on,
      null,
      v_student_branch_id,
      v_slot_id
    )
    returning id into v_series_id;
  exception
    when exclusion_violation then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_SERIES_TIME_CONFLICT';
  end;

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
    v_semester_id,
    'REGULAR_SCHEDULE_ADDED',
    p_effective_on,
    v_actor_id,
    jsonb_build_object(
      'scheduleSlotId', v_slot_id,
      'seriesId', v_series_id,
      'teacherId', p_teacher_id,
      'weekday', p_weekday,
      'startTime', p_start_time,
      'durationMinutes', p_duration_minutes
    )
  );

  return jsonb_build_object(
    'changed', true,
    'scheduleSlotId', v_slot_id,
    'seriesId', v_series_id,
    'semesterId', v_semester_id,
    'effectiveOn', p_effective_on,
    'teacherId', p_teacher_id,
    'weekday', p_weekday,
    'startTime', p_start_time,
    'durationMinutes', p_duration_minutes
  );
end;
$function$;

revoke all
on function public.add_regular_schedule(uuid, uuid, smallint, time, integer, date)
from public, anon;

grant execute
on function public.add_regular_schedule(uuid, uuid, smallint, time, integer, date)
to authenticated;

comment on function public.add_regular_schedule(uuid, uuid, smallint, time, integer, date) is
  'Adds a logical regular schedule from an effective semester boundary. The target semester must not already be active. Master or same-branch manager only.';


-- ============================================================
-- 3. END A REGULAR SCHEDULE
--
-- Untouched future default lessons are academy-canceled and
-- their returned rights are revoked. Past, already canceled,
-- rebooked, or individually moved lessons remain unchanged.
-- ============================================================

create or replace function public.end_regular_schedule(
  p_schedule_slot_id uuid,
  p_effective_on date
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
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_slot public.regular_schedule_slots%rowtype;
  v_student_active boolean;
  v_student_status public.student_status;
  v_lesson record;

  v_end_on date;
  v_canceled_lesson_count integer := 0;
  v_revoked_right_count integer := 0;
  v_hard_deleted boolean := false;
begin
  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
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
      message = 'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  select rs.*
  into v_slot
  from public.regular_schedule_slots rs
  where rs.id = p_schedule_slot_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_slot.branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.is_active, s.status
  into v_student_active, v_student_status
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = v_slot.student_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true
     or v_student_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_slot.ends_on is not null
     and v_slot.ends_on < p_effective_on then
    return jsonb_build_object(
      'changed', false,
      'scheduleSlotId', v_slot.id,
      'effectiveOn', v_slot.ends_on + 1,
      'canceledLessonCount', 0,
      'revokedRightCount', 0,
      'hardDeleted', false
    );
  end if;

  if p_effective_on <= v_slot.starts_on then
    if exists (
      select 1
      from public.lesson_rights r
      where r.schedule_slot_id = v_slot.id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_SCHEDULE_ALREADY_MATERIALIZED';
    end if;

    delete from public.lesson_series ls
    where ls.schedule_slot_id = v_slot.id;

    delete from public.regular_schedule_slots rs
    where rs.id = v_slot.id;

    v_hard_deleted := true;
  else
    v_end_on := p_effective_on - 1;

    update public.lesson_series ls
    set effective_until = v_end_on
    where ls.schedule_slot_id = v_slot.id
      and ls.effective_from < p_effective_on
      and (ls.effective_until is null or ls.effective_until >= p_effective_on);

    delete from public.lesson_series ls
    where ls.schedule_slot_id = v_slot.id
      and ls.effective_from >= p_effective_on
      and not exists (
        select 1
        from public.lessons l
        where l.series_id = ls.id
      );

    update public.regular_schedule_slots rs
    set ends_on = v_end_on
    where rs.id = v_slot.id;

    for v_lesson in
      select l.id as lesson_id, r.id as right_id
      from public.lesson_rights r
      join public.lessons l on l.lesson_right_id = r.id
      where r.schedule_slot_id = v_slot.id
        and r.origin = 'regular_base'::public.lesson_right_origin
        and r.status = 'reserved'::public.lesson_right_status
        and l.lesson_type = 'regular'::public.lesson_type
        and l.status = 'scheduled'::public.lesson_status
        and l.rescheduled_by is null
        and l.occurrence_at is not null
        and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
        and not exists (
          select 1
          from public.lesson_cancellation_events e
          where e.lesson_right_id = r.id
        )
      order by l.starts_at, l.id
      for update of l, r
    loop
      perform public.cancel_lesson(
        v_lesson.lesson_id,
        'regular_schedule_ended'
      );

      update public.lesson_rights r
      set
        status = 'revoked'::public.lesson_right_status,
        revoked_at = coalesce(r.revoked_at, pg_catalog.now())
      where r.id = v_lesson.right_id
        and r.status = 'available'::public.lesson_right_status;

      if found then
        v_revoked_right_count := v_revoked_right_count + 1;
      end if;

      v_canceled_lesson_count := v_canceled_lesson_count + 1;
    end loop;
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
    v_slot.student_id,
    v_slot.branch_id,
    null,
    'REGULAR_SCHEDULE_ENDED',
    p_effective_on,
    v_actor_id,
    jsonb_build_object(
      'scheduleSlotId', v_slot.id,
      'previousStartsOn', v_slot.starts_on,
      'previousEndsOn', v_slot.ends_on,
      'hardDeleted', v_hard_deleted,
      'canceledLessonCount', v_canceled_lesson_count,
      'revokedRightCount', v_revoked_right_count
    )
  );

  return jsonb_build_object(
    'changed', true,
    'scheduleSlotId', v_slot.id,
    'effectiveOn', p_effective_on,
    'canceledLessonCount', v_canceled_lesson_count,
    'revokedRightCount', v_revoked_right_count,
    'hardDeleted', v_hard_deleted
  );
end;
$function$;

revoke all
on function public.end_regular_schedule(uuid, date)
from public, anon;

grant execute
on function public.end_regular_schedule(uuid, date)
to authenticated;

comment on function public.end_regular_schedule(uuid, date) is
  'Ends a logical regular schedule from an effective date. Untouched future default lessons are academy-canceled and their rights revoked; past, canceled, rebooked, and individually moved lessons remain historical. Master or same-branch manager only.';
