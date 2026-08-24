alter table public.lessons
  add column if not exists manual_makeup_right_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'lessons_manual_makeup_right_id_fkey'
      and conrelid = 'public.lessons'::regclass
  ) then
    alter table public.lessons
      add constraint lessons_manual_makeup_right_id_fkey
      foreign key (manual_makeup_right_id)
      references public.lesson_rights(id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists lessons_manual_makeup_right_unique
  on public.lessons(manual_makeup_right_id)
  where manual_makeup_right_id is not null;

create or replace function public.create_managed_makeup_lesson(
  p_student_id uuid,
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_confirm_warnings boolean default false,
  p_reason text default null,
  p_deduct_lesson_right boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_result jsonb;
  v_lesson public.lessons%rowtype;
  v_semester_id uuid;
  v_right public.lesson_rights%rowtype;
  v_local_date date;
begin
  v_result := public.create_makeup_lesson(
    p_student_id,
    p_teacher_id,
    p_starts_at,
    p_duration_minutes,
    p_confirm_warnings,
    p_reason
  );

  if not coalesce(p_deduct_lesson_right, false)
     or coalesce((v_result ->> 'changed')::boolean, false) = false then
    return v_result || jsonb_build_object(
      'lessonRightDeducted', false,
      'lessonRightId', null
    );
  end if;

  select *
  into v_lesson
  from public.lessons l
  where l.id = (v_result ->> 'lessonId')::uuid
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MAKEUP_LESSON_NOT_FOUND_AFTER_CREATE';
  end if;

  v_local_date := (v_lesson.starts_at at time zone 'Asia/Seoul')::date;

  select s.id
  into v_semester_id
  from public.semesters s
  left join public.branch_semester_overrides o
    on o.semester_id = s.id
   and o.branch_id = v_lesson.branch_id
  where v_local_date between coalesce(o.starts_on, s.starts_on)
                         and coalesce(o.ends_on, s.ends_on)
  order by coalesce(o.starts_on, s.starts_on)
  limit 1;

  if v_semester_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND_FOR_DATE';
  end if;

  select r.*
  into v_right
  from public.lesson_rights r
  where r.student_id = p_student_id
    and r.branch_id = v_lesson.branch_id
    and r.usable_semester_id = v_semester_id
    and r.status = 'available'::public.lesson_right_status
    and r.duration_minutes = p_duration_minutes
  order by
    case when r.origin = 'carryover'::public.lesson_right_origin then 0 else 1 end,
    case when exists (
      select 1
      from public.lesson_cancellation_events e
      where e.lesson_right_id = r.id
    ) then 0 else 1 end,
    (
      select min(e.canceled_at)
      from public.lesson_cancellation_events e
      where e.lesson_right_id = r.id
    ) asc nulls last,
    r.sequence_no,
    r.id
  limit 1
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_NO_MATCHING_AVAILABLE_LESSON_RIGHT';
  end if;

  update public.lessons
  set manual_makeup_right_id = v_right.id
  where id = v_lesson.id;

  update public.lesson_rights
  set
    status = 'consumed'::public.lesson_right_status,
    consumed_at = pg_catalog.now(),
    reserved_at = null
  where id = v_right.id;

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
    v_lesson.branch_id,
    v_semester_id,
    'MAKEUP_LESSON_RIGHT_DEDUCTED',
    v_local_date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'rightId', v_right.id,
      'rightOrigin', v_right.origin,
      'durationMinutes', v_right.duration_minutes
    )
  );

  return v_result || jsonb_build_object(
    'lessonRightDeducted', true,
    'lessonRightId', v_right.id
  );
end;
$$;

revoke all on function public.create_managed_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text, boolean
) from public, anon;
grant execute on function public.create_managed_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text, boolean
) to authenticated;

create or replace function public.cancel_standalone_makeup_lesson(
  p_lesson_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_lesson public.lessons%rowtype;
  v_local_date date;
  v_semester_id uuid;
  v_reason text;
  v_right public.lesson_rights%rowtype;
  v_plan_status public.student_semester_plan_status;
  v_right_restored boolean := false;
begin
  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found or v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_MANAGEMENT_REQUIRED';
  end if;

  select *
  into v_lesson
  from public.lessons l
  where l.id = p_lesson_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_NOT_FOUND';
  end if;

  if v_lesson.lesson_type <> 'makeup'::public.lesson_type
     or v_lesson.series_id is not null
     or v_lesson.lesson_right_id is not null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STANDALONE_MAKEUP_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_lesson.branch_id) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if v_lesson.status <> 'scheduled'::public.lesson_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_NOT_SCHEDULED';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  v_local_date := (v_lesson.starts_at at time zone 'Asia/Seoul')::date;

  select s.id
  into v_semester_id
  from public.semesters s
  left join public.branch_semester_overrides o
    on o.semester_id = s.id
   and o.branch_id = v_lesson.branch_id
  where v_local_date between coalesce(o.starts_on, s.starts_on)
                         and coalesce(o.ends_on, s.ends_on)
  order by coalesce(o.starts_on, s.starts_on)
  limit 1;

  update public.lessons
  set
    status = 'canceled'::public.lesson_status,
    canceled_by = v_actor_id,
    canceled_at = pg_catalog.now(),
    cancellation_reason = coalesce(v_reason, 'academy_makeup_cancellation')
  where id = v_lesson.id
  returning * into v_lesson;

  if v_lesson.manual_makeup_right_id is not null then
    select *
    into v_right
    from public.lesson_rights r
    where r.id = v_lesson.manual_makeup_right_id
    for update;

    if found and v_right.status = 'consumed'::public.lesson_right_status then
      select sp.status
      into v_plan_status
      from public.student_semester_plans sp
      where sp.student_id = v_lesson.student_id
        and sp.semester_id = v_right.usable_semester_id
        and sp.branch_id = v_lesson.branch_id
      order by sp.created_at desc
      limit 1;

      if v_plan_status in (
        'planned'::public.student_semester_plan_status,
        'active'::public.student_semester_plan_status
      ) then
        update public.lesson_rights
        set
          status = 'available'::public.lesson_right_status,
          consumed_at = null,
          reserved_at = null
        where id = v_right.id;
        v_right_restored := true;
      end if;
    end if;
  end if;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    v_lesson.student_id,
    v_lesson.branch_id,
    v_semester_id,
    'MAKEUP_LESSON_CANCELED',
    v_local_date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'teacherId', v_lesson.teacher_id,
      'startsAt', v_lesson.starts_at,
      'endsAt', v_lesson.ends_at,
      'durationMinutes', v_lesson.duration_minutes,
      'reason', v_reason,
      'manualMakeupRightId', v_lesson.manual_makeup_right_id,
      'lessonRightRestored', v_right_restored
    )
  );

  return jsonb_build_object(
    'lessonId', v_lesson.id,
    'changed', true,
    'status', 'canceled',
    'lessonRightRestored', v_right_restored
  );
end;
$$;

create or replace function private.restore_manual_makeup_right_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.manual_makeup_right_id is not null
     and old.status = 'scheduled'::public.lesson_status
     and old.starts_at > pg_catalog.now() then
    update public.lesson_rights
    set
      status = 'available'::public.lesson_right_status,
      consumed_at = null,
      reserved_at = null
    where id = old.manual_makeup_right_id
      and status = 'consumed'::public.lesson_right_status;
  end if;

  return old;
end;
$$;

revoke all on function private.restore_manual_makeup_right_before_delete() from public, anon, authenticated;

drop trigger if exists restore_manual_makeup_right_before_delete on public.lessons;
create trigger restore_manual_makeup_right_before_delete
before delete on public.lessons
for each row
execute function private.restore_manual_makeup_right_before_delete();
