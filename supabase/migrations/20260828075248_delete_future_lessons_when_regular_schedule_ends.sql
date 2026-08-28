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
  v_deleted_lesson_count integer := 0;
  v_deleted_right_count integer := 0;
  v_hard_deleted boolean := false;
  v_linked_right_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using errcode='P0001', message='FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  select rs.* into v_slot
  from public.regular_schedule_slots rs
  where rs.id=p_schedule_slot_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';
  end if;

  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_slot.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.is_active,s.status into v_student_active,v_student_status
  from public.students s join public.profiles p on p.id=s.id
  where s.id=v_slot.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_slot.ends_on is not null and v_slot.ends_on < p_effective_on then
    return jsonb_build_object(
      'changed',false,
      'scheduleSlotId',v_slot.id,
      'effectiveOn',v_slot.ends_on+1,
      'canceledLessonCount',0,
      'revokedRightCount',0,
      'deletedLessonCount',0,
      'deletedRightCount',0,
      'hardDeleted',false
    );
  end if;

  if p_effective_on <= v_slot.starts_on then
    select count(*)::integer into v_linked_right_count
    from public.lesson_rights r
    where r.schedule_slot_id=v_slot.id;

    if v_linked_right_count=0 then
      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    else
      if exists (
        select 1
        from public.lesson_rights r
        left join public.lessons l on l.lesson_right_id=r.id
        where r.schedule_slot_id=v_slot.id
          and (
            r.origin <> 'regular_base'::public.lesson_right_origin
            or r.status <> 'reserved'::public.lesson_right_status
            or l.id is null
            or l.status <> 'scheduled'::public.lesson_status
            or l.rescheduled_by is not null
            or l.canceled_at is not null
            or l.starts_at <= pg_catalog.now()
          )
      ) or exists (
        select 1 from public.lesson_cancellation_events e
        join public.lesson_rights r on r.id=e.lesson_right_id
        where r.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lesson_rights child
        join public.lesson_rights source on source.id=child.source_right_id
        where source.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lessons m
        join public.lesson_rights r on r.id=m.manual_makeup_right_id
        where r.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lesson_rebooking_credits c
        join public.lessons l on l.id=c.source_lesson_id
        join public.lesson_rights r on r.id=l.lesson_right_id
        where r.schedule_slot_id=v_slot.id
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_MATERIALIZED_UNDO_UNSAFE';
      end if;

      delete from public.lessons l
      using public.lesson_rights r
      where l.lesson_right_id=r.id and r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_lesson_count=row_count;

      delete from public.lesson_rights r where r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_right_count=row_count;

      if v_deleted_right_count <> v_linked_right_count then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
      end if;

      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    end if;
  else
    v_end_on := p_effective_on-1;

    if exists (
      select 1
      from public.lesson_rights r
      where r.schedule_slot_id=v_slot.id
        and r.origin='regular_base'::public.lesson_right_origin
        and exists (
          select 1
          from public.lessons target_l
          where target_l.lesson_right_id=r.id
            and target_l.occurrence_at is not null
            and (target_l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
            and target_l.starts_at > pg_catalog.now()
        )
        and not (
          r.status='reserved'::public.lesson_right_status
          and (select count(*) from public.lessons l where l.lesson_right_id=r.id)=1
          and exists (
            select 1 from public.lessons l
            where l.lesson_right_id=r.id
              and l.lesson_type='regular'::public.lesson_type
              and l.status='scheduled'::public.lesson_status
              and l.rescheduled_by is null
              and l.canceled_at is null
              and l.cancellation_reason is null
              and l.occurrence_at is not null
              and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
              and l.starts_at > pg_catalog.now()
          )
          and not exists (
            select 1 from public.lesson_cancellation_events e
            where e.lesson_right_id=r.id
          )
        )
    ) or exists (
      select 1
      from public.lesson_rights source
      where source.schedule_slot_id=v_slot.id
        and source.origin='regular_base'::public.lesson_right_origin
        and exists (
          select 1 from public.lessons l
          where l.lesson_right_id=source.id
            and l.occurrence_at is not null
            and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
            and l.starts_at > pg_catalog.now()
        )
        and (
          exists (select 1 from public.lesson_rights child where child.source_right_id=source.id)
          or exists (select 1 from public.lessons m where m.manual_makeup_right_id=source.id)
          or exists (
            select 1 from public.lesson_rebooking_credits c
            join public.lessons l on l.id=c.source_lesson_id
            where l.lesson_right_id=source.id
          )
        )
    ) then
      raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_MATERIALIZED_UNDO_UNSAFE';
    end if;

    update public.lesson_series ls
    set effective_until=v_end_on
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from < p_effective_on
      and (ls.effective_until is null or ls.effective_until >= p_effective_on);

    delete from public.lesson_series ls
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from >= p_effective_on
      and not exists (select 1 from public.lessons l where l.series_id=ls.id);

    update public.regular_schedule_slots rs set ends_on=v_end_on where rs.id=v_slot.id;

    for v_lesson in
      select l.id as lesson_id,r.id as right_id
      from public.lesson_rights r
      join public.lessons l on l.lesson_right_id=r.id
      where r.schedule_slot_id=v_slot.id
        and r.origin='regular_base'::public.lesson_right_origin
        and r.status='reserved'::public.lesson_right_status
        and l.lesson_type='regular'::public.lesson_type
        and l.status='scheduled'::public.lesson_status
        and l.rescheduled_by is null
        and l.canceled_at is null
        and l.cancellation_reason is null
        and l.occurrence_at is not null
        and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
        and not exists (select 1 from public.lesson_cancellation_events e where e.lesson_right_id=r.id)
      order by l.starts_at,l.id
      for update of l,r
    loop
      delete from public.lessons l where l.id=v_lesson.lesson_id;
      if not found then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
      end if;
      v_deleted_lesson_count := v_deleted_lesson_count+1;

      delete from public.lesson_rights r where r.id=v_lesson.right_id;
      if not found then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
      end if;
      v_deleted_right_count := v_deleted_right_count+1;
    end loop;

    delete from public.lesson_series ls
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from >= p_effective_on
      and not exists (select 1 from public.lessons l where l.series_id=ls.id);
  end if;

  insert into public.audit_events(
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    v_slot.student_id,v_slot.branch_id,null,'REGULAR_SCHEDULE_ENDED',p_effective_on,v_actor_id,
    jsonb_build_object(
      'scheduleSlotId',v_slot.id,
      'previousStartsOn',v_slot.starts_on,
      'previousEndsOn',v_slot.ends_on,
      'hardDeleted',v_hard_deleted,
      'canceledLessonCount',0,
      'revokedRightCount',0,
      'deletedLessonCount',v_deleted_lesson_count,
      'deletedRightCount',v_deleted_right_count
    )
  );

  return jsonb_build_object(
    'changed',true,
    'scheduleSlotId',v_slot.id,
    'effectiveOn',p_effective_on,
    'canceledLessonCount',0,
    'revokedRightCount',0,
    'deletedLessonCount',v_deleted_lesson_count,
    'deletedRightCount',v_deleted_right_count,
    'hardDeleted',v_hard_deleted
  );
end;
$function$;

create temporary table regular_schedule_end_cleanup_targets on commit drop as
select
  r.id as right_id,
  l.id as lesson_id,
  l.student_id,
  l.branch_id
from public.lesson_rights r
join public.lessons l on l.lesson_right_id=r.id
where r.origin='regular_base'::public.lesson_right_origin
  and r.status='revoked'::public.lesson_right_status
  and l.lesson_type='regular'::public.lesson_type
  and l.status='canceled'::public.lesson_status
  and l.rescheduled_by is null
  and l.canceled_at is not null
  and l.cancellation_reason='regular_schedule_ended'
  and l.starts_at > pg_catalog.now()
  and (select count(*) from public.lessons l2 where l2.lesson_right_id=r.id)=1
  and (select count(*) from public.lesson_cancellation_events e where e.lesson_right_id=r.id)=1
  and exists (
    select 1 from public.lesson_cancellation_events e
    where e.lesson_right_id=r.id
      and e.origin='academy'::public.lesson_cancellation_origin
      and e.counts_toward_limit=false
      and e.reason='regular_schedule_ended'
  )
  and not exists (select 1 from public.lesson_rights child where child.source_right_id=r.id)
  and not exists (select 1 from public.lessons m where m.manual_makeup_right_id=r.id)
  and not exists (
    select 1 from public.lesson_rebooking_credits c
    where c.source_lesson_id=l.id
  );

alter table public.lesson_cancellation_events disable trigger lesson_cancellation_events_immutable;

delete from public.lesson_cancellation_events e
using regular_schedule_end_cleanup_targets t
where e.lesson_right_id=t.right_id;

delete from public.lessons l
using regular_schedule_end_cleanup_targets t
where l.id=t.lesson_id;

delete from public.lesson_rights r
using regular_schedule_end_cleanup_targets t
where r.id=t.right_id;

alter table public.lesson_cancellation_events enable trigger lesson_cancellation_events_immutable;

insert into public.audit_events(
  subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
)
select
  t.student_id,
  t.branch_id,
  null,
  'REGULAR_SCHEDULE_END_LEGACY_CLEANUP',
  (pg_catalog.now() at time zone 'Asia/Seoul')::date,
  null,
  jsonb_build_object(
    'deletedLegacyLessonCount',count(*),
    'reason','regular_schedule_ended',
    'executionSource','migration'
  )
from regular_schedule_end_cleanup_targets t
group by t.student_id,t.branch_id;
