create table private.student_withdrawal_lesson_snapshots (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  lesson_id uuid not null,
  withdrawal_date date not null,
  starts_at timestamptz not null,
  lesson_snapshot jsonb not null,
  lesson_right_id uuid,
  lesson_right_snapshot jsonb,
  manual_makeup_right_id uuid,
  manual_makeup_right_snapshot jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  closed_at timestamptz,
  resolution text,
  resolution_detail text,
  restored_lesson_id uuid,
  constraint student_withdrawal_lesson_snapshot_json_check
    check (jsonb_typeof(lesson_snapshot) = 'object'),
  constraint student_withdrawal_lesson_right_snapshot_json_check
    check (lesson_right_snapshot is null or jsonb_typeof(lesson_right_snapshot) = 'object'),
  constraint student_withdrawal_manual_right_snapshot_json_check
    check (manual_makeup_right_snapshot is null or jsonb_typeof(manual_makeup_right_snapshot) = 'object')
);

alter table private.student_withdrawal_lesson_snapshots enable row level security;
revoke all on table private.student_withdrawal_lesson_snapshots from public, anon, authenticated;

create unique index student_withdrawal_lesson_snapshots_active_unique
  on private.student_withdrawal_lesson_snapshots(student_id, lesson_id)
  where closed_at is null;

create index student_withdrawal_lesson_snapshots_active_student_starts_idx
  on private.student_withdrawal_lesson_snapshots(student_id, starts_at)
  where closed_at is null;

create or replace function private.preclear_student_withdrawal_lessons(
  p_student_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cutoff timestamptz;
  v_lesson public.lessons%rowtype;
  v_lesson_right_snapshot jsonb;
  v_manual_right_snapshot jsonb;
  v_deleted_count integer := 0;
  v_deleted_ids uuid[] := '{}'::uuid[];
begin
  if p_student_id is null or p_withdrawal_date is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_WITHDRAWAL_PRECLEAR_ARGUMENT_REQUIRED';
  end if;

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
    if exists (
      select 1
      from public.lesson_rebooking_credits c
      where c.source_lesson_id = v_lesson.id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_WITHDRAWAL_PRECLEAR_LEGACY_CREDIT_UNSAFE',
        detail = 'lesson_id=' || v_lesson.id::text;
    end if;

    v_lesson_right_snapshot := null;
    if v_lesson.lesson_right_id is not null then
      select to_jsonb(r.*)
      into v_lesson_right_snapshot
      from public.lesson_rights r
      where r.id = v_lesson.lesson_right_id
      for update;

      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_PRECLEAR_RIGHT_NOT_FOUND',
          detail = 'lesson_id=' || v_lesson.id::text;
      end if;
    end if;

    v_manual_right_snapshot := null;
    if v_lesson.manual_makeup_right_id is not null then
      select to_jsonb(r.*)
      into v_manual_right_snapshot
      from public.lesson_rights r
      where r.id = v_lesson.manual_makeup_right_id
      for update;

      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_PRECLEAR_MANUAL_RIGHT_NOT_FOUND',
          detail = 'lesson_id=' || v_lesson.id::text;
      end if;
    end if;

    insert into private.student_withdrawal_lesson_snapshots (
      student_id,
      lesson_id,
      withdrawal_date,
      starts_at,
      lesson_snapshot,
      lesson_right_id,
      lesson_right_snapshot,
      manual_makeup_right_id,
      manual_makeup_right_snapshot
    ) values (
      p_student_id,
      v_lesson.id,
      p_withdrawal_date,
      v_lesson.starts_at,
      to_jsonb(v_lesson),
      v_lesson.lesson_right_id,
      v_lesson_right_snapshot,
      v_lesson.manual_makeup_right_id,
      v_manual_right_snapshot
    );

    delete from public.lessons l
    where l.id = v_lesson.id;

    if v_lesson.manual_makeup_right_id is not null
       and v_manual_right_snapshot is not null then
      update public.lesson_rights r
      set
        status = (v_manual_right_snapshot ->> 'status')::public.lesson_right_status,
        reserved_at = (v_manual_right_snapshot ->> 'reserved_at')::timestamptz,
        consumed_at = (v_manual_right_snapshot ->> 'consumed_at')::timestamptz,
        expired_at = (v_manual_right_snapshot ->> 'expired_at')::timestamptz,
        revoked_at = (v_manual_right_snapshot ->> 'revoked_at')::timestamptz
      where r.id = v_lesson.manual_makeup_right_id;
    end if;

    v_deleted_count := v_deleted_count + 1;
    v_deleted_ids := array_append(v_deleted_ids, v_lesson.id);
  end loop;

  return jsonb_build_object(
    'deletedLessonCount', v_deleted_count,
    'deletedLessonIds', to_jsonb(v_deleted_ids)
  );
end;
$function$;

revoke execute on function private.preclear_student_withdrawal_lessons(uuid, date)
  from public, anon, authenticated;

create or replace function private.restore_student_withdrawal_snapshots(
  p_student_id uuid,
  p_restore_before timestamptz,
  p_actor_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_snapshot private.student_withdrawal_lesson_snapshots%rowtype;
  v_lesson public.lessons%rowtype;
  v_local_date date;
  v_current_right_status public.lesson_right_status;
  v_expected_right_status public.lesson_right_status;
  v_restore_error text;
  v_restored_count integer := 0;
  v_credit_count integer := 0;
  v_unrestored_count integer := 0;
begin
  for v_snapshot in
    select s.*
    from private.student_withdrawal_lesson_snapshots s
    where s.student_id = p_student_id
      and s.closed_at is null
      and (p_restore_before is null or s.starts_at < p_restore_before)
    order by s.starts_at, s.id
    for update
  loop
    select *
    into v_lesson
    from pg_catalog.jsonb_populate_record(
      null::public.lessons,
      v_snapshot.lesson_snapshot
    );

    v_restore_error := null;

    begin
      if exists (
        select 1 from public.lessons l where l.id = v_lesson.id
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_RESTORE_LESSON_ID_TAKEN';
      end if;

      if v_snapshot.lesson_right_id is not null then
        v_expected_right_status :=
          (v_snapshot.lesson_right_snapshot ->> 'status')::public.lesson_right_status;

        select r.status
        into v_current_right_status
        from public.lesson_rights r
        where r.id = v_snapshot.lesson_right_id
        for update;

        if not found or v_current_right_status is distinct from v_expected_right_status then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_RESTORE_RIGHT_CHANGED';
        end if;

        if exists (
          select 1
          from public.lessons l
          where l.lesson_right_id = v_snapshot.lesson_right_id
        ) then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_RESTORE_RIGHT_ALREADY_USED';
        end if;
      end if;

      if v_snapshot.manual_makeup_right_id is not null then
        v_expected_right_status :=
          (v_snapshot.manual_makeup_right_snapshot ->> 'status')::public.lesson_right_status;

        select r.status
        into v_current_right_status
        from public.lesson_rights r
        where r.id = v_snapshot.manual_makeup_right_id
        for update;

        if not found or v_current_right_status is distinct from v_expected_right_status then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_RESTORE_MANUAL_RIGHT_CHANGED';
        end if;

        if exists (
          select 1
          from public.lessons l
          where l.manual_makeup_right_id = v_snapshot.manual_makeup_right_id
        ) then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_RESTORE_MANUAL_RIGHT_ALREADY_USED';
        end if;
      end if;

      v_local_date := (v_lesson.starts_at at time zone 'Asia/Seoul')::date;

      if v_lesson.lesson_type in (
        'regular'::public.lesson_type,
        'flex'::public.lesson_type
      ) and not exists (
        select 1
        from public.teacher_student_assignments a
        where a.student_id = v_lesson.student_id
          and a.teacher_id = v_lesson.teacher_id
          and a.branch_id is not distinct from v_lesson.branch_id
          and a.starts_on <= v_local_date
          and (a.ends_on is null or a.ends_on >= v_local_date)
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_RESTORE_ASSIGNMENT_CHANGED';
      end if;

      if not exists (
        select 1
        from private.teacher_work_hours_for_date(v_lesson.teacher_id, v_local_date) wh
        where wh.start_time <= (v_lesson.starts_at at time zone 'Asia/Seoul')::time
          and wh.end_time >= (v_lesson.ends_at at time zone 'Asia/Seoul')::time
          and (v_lesson.starts_at at time zone 'Asia/Seoul')::date =
              (v_lesson.ends_at at time zone 'Asia/Seoul')::date
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_RESTORE_OUTSIDE_WORK_HOURS';
      end if;

      if exists (
        select 1
        from public.closure_periods cp
        where cp.branch_id = v_lesson.branch_id
          and v_local_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_RESTORE_ON_CLOSURE';
      end if;

      if exists (
        select 1
        from public.blocked_periods bp
        where bp.teacher_id = v_lesson.teacher_id
          and tstzrange(bp.starts_at, bp.ends_at, '[)') &&
              tstzrange(v_lesson.starts_at, v_lesson.ends_at, '[)')
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_WITHDRAWAL_RESTORE_BLOCKED';
      end if;

      insert into public.lessons (
        id,
        series_id,
        student_id,
        teacher_id,
        occurrence_at,
        starts_at,
        duration_minutes,
        lesson_type,
        status,
        rescheduled_by,
        canceled_by,
        canceled_at,
        cancellation_reason,
        created_at,
        updated_at,
        branch_id,
        lesson_right_id,
        manual_makeup_right_id
      ) values (
        v_lesson.id,
        v_lesson.series_id,
        v_lesson.student_id,
        v_lesson.teacher_id,
        v_lesson.occurrence_at,
        v_lesson.starts_at,
        v_lesson.duration_minutes,
        v_lesson.lesson_type,
        'scheduled'::public.lesson_status,
        v_lesson.rescheduled_by,
        null,
        null,
        null,
        v_lesson.created_at,
        v_lesson.updated_at,
        v_lesson.branch_id,
        v_lesson.lesson_right_id,
        v_lesson.manual_makeup_right_id
      );

      update private.student_withdrawal_lesson_snapshots s
      set
        closed_at = pg_catalog.now(),
        resolution = 'restored',
        resolution_detail = p_reason,
        restored_lesson_id = v_lesson.id
      where s.id = v_snapshot.id;

      v_restored_count := v_restored_count + 1;
      continue;

    exception
      when others then
        v_restore_error := sqlerrm;
    end;

    if v_snapshot.lesson_right_id is not null
       and (v_snapshot.lesson_right_snapshot ->> 'status') = 'reserved' then
      begin
        select r.status
        into v_current_right_status
        from public.lesson_rights r
        where r.id = v_snapshot.lesson_right_id
        for update;

        if not found or v_current_right_status <> 'reserved'::public.lesson_right_status then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_CREDIT_RIGHT_CHANGED';
        end if;

        if exists (
          select 1
          from public.lessons l
          where l.id = v_lesson.id
             or l.lesson_right_id = v_snapshot.lesson_right_id
        ) then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_CREDIT_LESSON_ALREADY_EXISTS';
        end if;

        insert into public.lessons (
          id,
          series_id,
          student_id,
          teacher_id,
          occurrence_at,
          starts_at,
          duration_minutes,
          lesson_type,
          status,
          rescheduled_by,
          canceled_by,
          canceled_at,
          cancellation_reason,
          created_at,
          updated_at,
          branch_id,
          lesson_right_id,
          manual_makeup_right_id
        ) values (
          v_lesson.id,
          v_lesson.series_id,
          v_lesson.student_id,
          v_lesson.teacher_id,
          v_lesson.occurrence_at,
          v_lesson.starts_at,
          v_lesson.duration_minutes,
          v_lesson.lesson_type,
          'canceled'::public.lesson_status,
          v_lesson.rescheduled_by,
          p_actor_id,
          pg_catalog.now(),
          'withdrawal_reversal_original_slot_unavailable',
          v_lesson.created_at,
          pg_catalog.now(),
          v_lesson.branch_id,
          v_lesson.lesson_right_id,
          null
        );

        update public.lesson_rights r
        set
          status = 'available'::public.lesson_right_status,
          reserved_at = null
        where r.id = v_snapshot.lesson_right_id;

        update private.student_withdrawal_lesson_snapshots s
        set
          closed_at = pg_catalog.now(),
          resolution = 'credit',
          resolution_detail = v_restore_error,
          restored_lesson_id = v_lesson.id
        where s.id = v_snapshot.id;

        v_credit_count := v_credit_count + 1;
        continue;
      exception
        when others then
          v_restore_error := coalesce(v_restore_error || ' | ', '') || sqlerrm;
      end;
    end if;

    if v_snapshot.manual_makeup_right_id is not null
       and (v_snapshot.manual_makeup_right_snapshot ->> 'status') = 'consumed' then
      begin
        select r.status
        into v_current_right_status
        from public.lesson_rights r
        where r.id = v_snapshot.manual_makeup_right_id
        for update;

        if not found or v_current_right_status <> 'consumed'::public.lesson_right_status then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_CREDIT_MANUAL_RIGHT_CHANGED';
        end if;

        if exists (
          select 1
          from public.lessons l
          where l.manual_makeup_right_id = v_snapshot.manual_makeup_right_id
        ) then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_WITHDRAWAL_CREDIT_MANUAL_RIGHT_ALREADY_USED';
        end if;

        update public.lesson_rights r
        set
          status = 'available'::public.lesson_right_status,
          consumed_at = null,
          reserved_at = null
        where r.id = v_snapshot.manual_makeup_right_id;

        update private.student_withdrawal_lesson_snapshots s
        set
          closed_at = pg_catalog.now(),
          resolution = 'credit',
          resolution_detail = v_restore_error
        where s.id = v_snapshot.id;

        v_credit_count := v_credit_count + 1;
        continue;
      exception
        when others then
          v_restore_error := coalesce(v_restore_error || ' | ', '') || sqlerrm;
      end;
    end if;

    update private.student_withdrawal_lesson_snapshots s
    set
      closed_at = pg_catalog.now(),
      resolution = 'not_restored',
      resolution_detail = v_restore_error
    where s.id = v_snapshot.id;

    v_unrestored_count := v_unrestored_count + 1;
  end loop;

  return jsonb_build_object(
    'restoredLessonCount', v_restored_count,
    'creditedLessonCount', v_credit_count,
    'unrestoredLessonCount', v_unrestored_count
  );
end;
$function$;

revoke execute on function private.restore_student_withdrawal_snapshots(uuid, timestamptz, uuid, text)
  from public, anon, authenticated;

create or replace function private.close_withdrawal_snapshots_after_student_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'withdrawn'::public.student_status
     and old.status is distinct from new.status then
    update private.student_withdrawal_lesson_snapshots s
    set
      closed_at = pg_catalog.now(),
      resolution = 'finalized',
      resolution_detail = 'student_withdrawal_finalized'
    where s.student_id = new.id
      and s.closed_at is null;
  end if;

  return new;
end;
$function$;

revoke execute on function private.close_withdrawal_snapshots_after_student_finalization()
  from public, anon, authenticated;

drop trigger if exists students_close_withdrawal_snapshots_after_finalization on public.students;
create trigger students_close_withdrawal_snapshots_after_finalization
after update of status on public.students
for each row
execute function private.close_withdrawal_snapshots_after_student_finalization();

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
  v_restore_before timestamptz;
  v_preclear jsonb := jsonb_build_object('deletedLessonCount', 0, 'deletedLessonIds', '[]'::jsonb);
  v_restore jsonb := jsonb_build_object('restoredLessonCount', 0, 'creditedLessonCount', 0, 'unrestoredLessonCount', 0);
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;

  if p_withdrawal_date is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if p_withdrawal_date < v_today then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_DATE_IN_PAST';
  end if;

  select p.branch_id, s.status, s.withdrawal_date
  into v_branch_id, v_status, v_current_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
  for update of s, p;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_branch_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  update public.students
  set withdrawal_date = p_withdrawal_date
  where id = p_student_id;

  if v_current_withdrawal_date is not null
     and p_withdrawal_date > v_current_withdrawal_date then
    v_restore_before := p_withdrawal_date::timestamp at time zone 'Asia/Seoul';
    v_restore := private.restore_student_withdrawal_snapshots(
      p_student_id,
      v_restore_before,
      v_actor_id,
      'withdrawal_date_moved_later'
    );
  end if;

  v_preclear := private.preclear_student_withdrawal_lessons(
    p_student_id,
    p_withdrawal_date
  );

  if v_current_withdrawal_date is distinct from p_withdrawal_date then
    insert into public.audit_events (
      subject_profile_id,
      branch_id,
      semester_id,
      event_type,
      effective_on,
      actor_id,
      details
    ) values (
      p_student_id,
      v_branch_id,
      null,
      'STUDENT_WITHDRAWAL_SCHEDULED',
      p_withdrawal_date,
      v_actor_id,
      jsonb_build_object(
        'previousWithdrawalDate', v_current_withdrawal_date,
        'withdrawalDate', p_withdrawal_date,
        'deletedLessonCount', coalesce((v_preclear ->> 'deletedLessonCount')::integer, 0),
        'deletedLessonIds', coalesce(v_preclear -> 'deletedLessonIds', '[]'::jsonb),
        'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
        'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
        'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
      )
    );
  end if;

  return jsonb_build_object(
    'changed', v_current_withdrawal_date is distinct from p_withdrawal_date,
    'studentId', p_student_id,
    'previousWithdrawalDate', v_current_withdrawal_date,
    'withdrawalDate', p_withdrawal_date,
    'deletedLessonCount', coalesce((v_preclear ->> 'deletedLessonCount')::integer, 0),
    'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
    'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
    'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
  );
end;
$function$;

create or replace function public.cancel_student_withdrawal(
  p_student_id uuid
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
  v_withdrawal_date date;
  v_today date;
  v_restore jsonb;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;

  select p.branch_id, s.status, s.withdrawal_date
  into v_branch_id, v_status, v_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
  for update of s, p;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_branch_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if v_withdrawal_date is null then
    return jsonb_build_object(
      'changed', false,
      'studentId', p_student_id,
      'withdrawalDate', null,
      'restoredLessonCount', 0,
      'creditedLessonCount', 0,
      'unrestoredLessonCount', 0
    );
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if v_withdrawal_date <= v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE';
  end if;

  update public.students
  set withdrawal_date = null
  where id = p_student_id;

  v_restore := private.restore_student_withdrawal_snapshots(
    p_student_id,
    null,
    v_actor_id,
    'withdrawal_canceled'
  );

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    p_student_id,
    v_branch_id,
    null,
    'STUDENT_WITHDRAWAL_CANCELED',
    v_today,
    v_actor_id,
    jsonb_build_object(
      'canceledWithdrawalDate', v_withdrawal_date,
      'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
      'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
      'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
    )
  );

  return jsonb_build_object(
    'changed', true,
    'studentId', p_student_id,
    'canceledWithdrawalDate', v_withdrawal_date,
    'withdrawalDate', null,
    'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
    'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
    'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
  );
end;
$function$;

do $migration$
declare
  v_student record;
begin
  for v_student in
    select s.id, s.withdrawal_date
    from public.students s
    where s.status = 'active'::public.student_status
      and s.withdrawal_date is not null
      and s.withdrawal_date >= (pg_catalog.now() at time zone 'Asia/Seoul')::date
  loop
    perform private.preclear_student_withdrawal_lessons(
      v_student.id,
      v_student.withdrawal_date
    );
  end loop;
end;
$migration$;