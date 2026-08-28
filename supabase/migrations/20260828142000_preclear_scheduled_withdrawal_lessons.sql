-- Future-dated withdrawal behavior:
-- 1) scheduling/changing a withdrawal immediately frees lessons on/after the date;
-- 2) rights-backed lessons return the same right to available;
-- 3) canceling/postponing a withdrawal restores lessons when their original slot is still valid;
-- 4) if a slot is no longer available, the lesson stays canceled and its right stays available.
--
-- No lesson/right history is deleted here. Final withdrawal remains responsible for
-- hard cleanup and revocation on the effective date.

create or replace function private.restore_scheduled_withdrawal_lessons(
  p_student_id uuid,
  p_cycle_boundary timestamptz,
  p_restore_before timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_lesson public.lessons%rowtype;
  v_right_status public.lesson_right_status;
  v_manual_right_status public.lesson_right_status;
  v_local_date date;
  v_local_start timestamp;
  v_local_end timestamp;
  v_can_restore boolean;
  v_restored_ids uuid[] := '{}'::uuid[];
  v_conflict_ids uuid[] := '{}'::uuid[];
  v_skipped_ids uuid[] := '{}'::uuid[];
  v_restored_right_count integer := 0;
begin
  for v_lesson in
    select l.*
    from public.lessons l
    where l.student_id = p_student_id
      and l.status = 'canceled'::public.lesson_status
      and l.cancellation_reason = 'scheduled_withdrawal'
      and l.canceled_at is not null
      and l.canceled_at > coalesce(p_cycle_boundary, '-infinity'::timestamptz)
      and (p_restore_before is null or l.starts_at < p_restore_before)
    order by l.starts_at, l.id
    for update
  loop
    v_local_date := (v_lesson.starts_at at time zone 'Asia/Seoul')::date;
    v_local_start := v_lesson.starts_at at time zone 'Asia/Seoul';
    v_local_end := v_lesson.ends_at at time zone 'Asia/Seoul';
    v_can_restore := true;

    -- A right may have been used elsewhere while the withdrawal was pending.
    if v_lesson.lesson_right_id is not null then
      select r.status
      into v_right_status
      from public.lesson_rights r
      where r.id = v_lesson.lesson_right_id
      for update;

      if not found or v_right_status <> 'available'::public.lesson_right_status then
        v_skipped_ids := array_append(v_skipped_ids, v_lesson.id);
        continue;
      end if;
    end if;

    if v_lesson.manual_makeup_right_id is not null then
      select r.status
      into v_manual_right_status
      from public.lesson_rights r
      where r.id = v_lesson.manual_makeup_right_id
      for update;

      if not found or v_manual_right_status <> 'available'::public.lesson_right_status then
        v_skipped_ids := array_append(v_skipped_ids, v_lesson.id);
        continue;
      end if;
    end if;

    -- Teacher/assignment must still be valid for the original appointment.
    if not exists (
      select 1
      from public.profiles tp
      join public.teachers t on t.id = tp.id
      where tp.id = v_lesson.teacher_id
        and tp.is_active = true
        and tp.branch_id = v_lesson.branch_id
        and tp.role in ('teacher'::public.user_role, 'manager'::public.user_role)
        and (t.withdrawal_date is null or v_local_date < t.withdrawal_date)
    ) then
      v_can_restore := false;
    end if;

    if v_can_restore and not exists (
      select 1
      from public.teacher_student_assignments a
      where a.student_id = p_student_id
        and a.teacher_id = v_lesson.teacher_id
        and a.branch_id = v_lesson.branch_id
        and a.starts_on <= v_local_date
        and (a.ends_on is null or a.ends_on >= v_local_date)
    ) then
      v_can_restore := false;
    end if;

    if v_can_restore and exists (
      select 1
      from public.closure_periods cp
      where cp.branch_id = v_lesson.branch_id
        and v_local_date between cp.starts_on and cp.ends_on
    ) then
      v_can_restore := false;
    end if;

    if v_can_restore and exists (
      select 1
      from public.blocked_periods bp
      where bp.teacher_id = v_lesson.teacher_id
        and tstzrange(bp.starts_at, bp.ends_at, '[)')
            && tstzrange(v_lesson.starts_at, v_lesson.ends_at, '[)')
    ) then
      v_can_restore := false;
    end if;

    if v_can_restore and not exists (
      select 1
      from private.teacher_work_hours_for_date(v_lesson.teacher_id, v_local_date) wh
      where wh.teacher_id = v_lesson.teacher_id
        and wh.weekday = extract(isodow from v_local_date)::smallint
        and wh.start_time <= v_local_start::time
        and wh.end_time >= v_local_end::time
    ) then
      v_can_restore := false;
    end if;

    if not v_can_restore then
      v_conflict_ids := array_append(v_conflict_ids, v_lesson.id);
      continue;
    end if;

    begin
      update public.lessons
      set
        status = 'scheduled'::public.lesson_status,
        canceled_by = null,
        canceled_at = null,
        cancellation_reason = null
      where id = v_lesson.id;

      if v_lesson.lesson_right_id is not null then
        update public.lesson_rights
        set
          status = 'reserved'::public.lesson_right_status,
          reserved_at = pg_catalog.now(),
          consumed_at = null,
          revoked_at = null
        where id = v_lesson.lesson_right_id
          and status = 'available'::public.lesson_right_status;

        if found then
          v_restored_right_count := v_restored_right_count + 1;
        end if;
      elsif v_lesson.manual_makeup_right_id is not null then
        update public.lesson_rights
        set
          status = 'consumed'::public.lesson_right_status,
          consumed_at = pg_catalog.now(),
          reserved_at = null,
          revoked_at = null
        where id = v_lesson.manual_makeup_right_id
          and status = 'available'::public.lesson_right_status;
      end if;

      v_restored_ids := array_append(v_restored_ids, v_lesson.id);
    exception
      when exclusion_violation then
        -- Another lesson has claimed the old student/teacher time. Keep the
        -- lesson canceled and, for rights-backed lessons, keep the right available.
        v_conflict_ids := array_append(v_conflict_ids, v_lesson.id);
    end;
  end loop;

  return jsonb_build_object(
    'restoredLessonCount', cardinality(v_restored_ids),
    'restoredLessonIds', to_jsonb(v_restored_ids),
    'conflictLessonCount', cardinality(v_conflict_ids),
    'conflictLessonIds', to_jsonb(v_conflict_ids),
    'skippedLessonCount', cardinality(v_skipped_ids),
    'skippedLessonIds', to_jsonb(v_skipped_ids),
    'restoredRightCount', v_restored_right_count
  );
end;
$function$;

create or replace function private.cancel_lessons_for_scheduled_withdrawal(
  p_student_id uuid,
  p_withdrawal_date date,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cutoff timestamptz;
  v_lesson public.lessons%rowtype;
  v_result jsonb;
  v_canceled_ids uuid[] := '{}'::uuid[];
  v_right_returned_count integer := 0;
  v_standalone_count integer := 0;
  v_legacy_count integer := 0;
begin
  v_cutoff := p_withdrawal_date::timestamp at time zone 'Asia/Seoul';

  for v_lesson in
    select l.*
    from public.lessons l
    where l.student_id = p_student_id
      and l.status = 'scheduled'::public.lesson_status
      and l.starts_at >= v_cutoff
    order by l.starts_at, l.id
    for update
  loop
    if v_lesson.lesson_right_id is not null then
      v_result := public.cancel_lesson(v_lesson.id, 'scheduled_withdrawal');
      v_right_returned_count := v_right_returned_count + 1;

    elsif v_lesson.lesson_type = 'makeup'::public.lesson_type
          and v_lesson.series_id is null then
      v_result := public.cancel_standalone_makeup_lesson(
        v_lesson.id,
        'scheduled_withdrawal'
      );
      v_standalone_count := v_standalone_count + 1;

    else
      -- Legacy/no-right fallback. Current production future regular lessons are
      -- rights-backed, but this keeps withdrawal scheduling safe for old rows.
      update public.lessons
      set
        status = 'canceled'::public.lesson_status,
        canceled_by = p_actor_id,
        canceled_at = pg_catalog.now(),
        cancellation_reason = 'scheduled_withdrawal'
      where id = v_lesson.id;

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
        v_lesson.branch_id,
        null,
        'LESSON_CANCELED',
        (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
        p_actor_id,
        jsonb_build_object(
          'lessonId', v_lesson.id,
          'cancellationOrigin', 'academy',
          'countsTowardLimit', false,
          'reason', 'scheduled_withdrawal',
          'legacyWithoutLessonRight', true
        )
      );

      v_legacy_count := v_legacy_count + 1;
    end if;

    v_canceled_ids := array_append(v_canceled_ids, v_lesson.id);
  end loop;

  return jsonb_build_object(
    'canceledLessonCount', cardinality(v_canceled_ids),
    'canceledLessonIds', to_jsonb(v_canceled_ids),
    'returnedRightCount', v_right_returned_count,
    'standaloneMakeupCount', v_standalone_count,
    'legacyLessonCount', v_legacy_count
  );
end;
$function$;

create or replace function public.schedule_student_withdrawal(
  p_student_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_branch_id uuid;
  v_status public.student_status;
  v_current_withdrawal_date date;
  v_today date;
  v_cycle_boundary timestamptz;
  v_new_cutoff timestamptz;
  v_restore_result jsonb := '{}'::jsonb;
  v_cancel_result jsonb := '{}'::jsonb;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;

  if p_withdrawal_date is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if p_withdrawal_date < v_today then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_DATE_IN_PAST';
  end if;

  select p.branch_id, s.status, s.withdrawal_date
  into v_branch_id, v_status, v_current_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
  for update of s, p;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if v_current_withdrawal_date = p_withdrawal_date then
    return jsonb_build_object(
      'changed', false,
      'studentId', p_student_id,
      'withdrawalDate', p_withdrawal_date,
      'canceledLessonCount', 0,
      'restoredLessonCount', 0,
      'restoreConflictLessonCount', 0
    );
  end if;

  select max(a.created_at)
  into v_cycle_boundary
  from public.audit_events a
  where a.subject_profile_id = p_student_id
    and a.event_type in ('STUDENT_WITHDRAWAL_CANCELED', 'STUDENT_WITHDRAWAL_FINALIZED');

  -- Set the new boundary first so restoration before the new date passes the
  -- canonical withdrawal trigger. The transaction rolls back as one unit on error.
  update public.students
  set withdrawal_date = p_withdrawal_date
  where id = p_student_id;

  v_new_cutoff := p_withdrawal_date::timestamp at time zone 'Asia/Seoul';

  if v_current_withdrawal_date is not null
     and p_withdrawal_date > v_current_withdrawal_date then
    v_restore_result := private.restore_scheduled_withdrawal_lessons(
      p_student_id,
      v_cycle_boundary,
      v_new_cutoff
    );
  end if;

  v_cancel_result := private.cancel_lessons_for_scheduled_withdrawal(
    p_student_id,
    p_withdrawal_date,
    v_actor_id
  );

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
    v_branch_id,
    null,
    'STUDENT_WITHDRAWAL_SCHEDULED',
    p_withdrawal_date,
    v_actor_id,
    jsonb_build_object(
      'previousWithdrawalDate', v_current_withdrawal_date,
      'withdrawalDate', p_withdrawal_date,
      'immediateLessonClearing', true,
      'cancellation', v_cancel_result,
      'restorationAfterDateExtension', v_restore_result
    )
  );

  return jsonb_build_object(
    'changed', true,
    'studentId', p_student_id,
    'previousWithdrawalDate', v_current_withdrawal_date,
    'withdrawalDate', p_withdrawal_date,
    'canceledLessonCount', coalesce((v_cancel_result->>'canceledLessonCount')::integer, 0),
    'returnedRightCount', coalesce((v_cancel_result->>'returnedRightCount')::integer, 0),
    'restoredLessonCount', coalesce((v_restore_result->>'restoredLessonCount')::integer, 0),
    'restoreConflictLessonCount', coalesce((v_restore_result->>'conflictLessonCount')::integer, 0)
  );
end;
$function$;

create or replace function public.cancel_student_withdrawal(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_branch_id uuid;
  v_status public.student_status;
  v_withdrawal_date date;
  v_today date;
  v_cycle_boundary timestamptz;
  v_restore_result jsonb := '{}'::jsonb;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;

  select p.branch_id, s.status, s.withdrawal_date
  into v_branch_id, v_status, v_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
  for update of s, p;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if v_withdrawal_date is null then
    return jsonb_build_object(
      'changed', false,
      'studentId', p_student_id,
      'withdrawalDate', null,
      'restoredLessonCount', 0,
      'restoreConflictLessonCount', 0
    );
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if v_withdrawal_date <= v_today then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE';
  end if;

  select max(a.created_at)
  into v_cycle_boundary
  from public.audit_events a
  where a.subject_profile_id = p_student_id
    and a.event_type in ('STUDENT_WITHDRAWAL_CANCELED', 'STUDENT_WITHDRAWAL_FINALIZED');

  -- Clear the withdrawal boundary before restoration; otherwise the canonical
  -- lesson trigger would correctly reject restoring lessons on/after that date.
  update public.students
  set withdrawal_date = null
  where id = p_student_id;

  v_restore_result := private.restore_scheduled_withdrawal_lessons(
    p_student_id,
    v_cycle_boundary,
    null
  );

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
    v_branch_id,
    null,
    'STUDENT_WITHDRAWAL_CANCELED',
    v_today,
    v_actor_id,
    jsonb_build_object(
      'canceledWithdrawalDate', v_withdrawal_date,
      'restoration', v_restore_result
    )
  );

  return jsonb_build_object(
    'changed', true,
    'studentId', p_student_id,
    'canceledWithdrawalDate', v_withdrawal_date,
    'withdrawalDate', null,
    'restoredLessonCount', coalesce((v_restore_result->>'restoredLessonCount')::integer, 0),
    'restoreConflictLessonCount', coalesce((v_restore_result->>'conflictLessonCount')::integer, 0),
    'availableRightCount',
      coalesce((v_restore_result->>'conflictLessonCount')::integer, 0)
      + coalesce((v_restore_result->>'skippedLessonCount')::integer, 0)
  );
end;
$function$;

revoke all on function private.restore_scheduled_withdrawal_lessons(uuid,timestamptz,timestamptz) from public;
revoke all on function private.cancel_lessons_for_scheduled_withdrawal(uuid,date,uuid) from public;
