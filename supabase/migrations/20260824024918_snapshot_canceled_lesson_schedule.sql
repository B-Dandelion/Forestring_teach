-- Preserve the scheduled occurrence on each immutable cancellation event.
-- Existing events stay nullable because their historical booking time cannot
-- always be reconstructed after later rebooking.

alter table public.lesson_cancellation_events
  add column if not exists lesson_starts_at timestamptz,
  add column if not exists lesson_duration_minutes integer;

comment on column public.lesson_cancellation_events.lesson_starts_at is
  'Lesson start time captured when this cancellation event was created.';

comment on column public.lesson_cancellation_events.lesson_duration_minutes is
  'Lesson duration captured when this cancellation event was created.';

do $migration$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.cancel_lesson(uuid,text)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'public.cancel_lesson(uuid,text) was not found';
  end if;

  v_updated := replace(
    v_definition,
$old$
  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    reason
  )
  values (
    v_lesson.id,
    v_right.id,
    v_right.student_id,
    v_right.branch_id,
    v_origin,
    v_actor_id,
    v_counts_toward_limit,
    v_reason
  )
$old$,
$new$
  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    reason,
    lesson_starts_at,
    lesson_duration_minutes
  )
  values (
    v_lesson.id,
    v_right.id,
    v_right.student_id,
    v_right.branch_id,
    v_origin,
    v_actor_id,
    v_counts_toward_limit,
    v_reason,
    v_lesson.starts_at,
    v_lesson.duration_minutes
  )
$new$
  );

  if v_updated = v_definition then
    raise exception 'Expected cancellation event insert was not found';
  end if;

  execute v_updated;
end;
$migration$;

revoke all
on function public.cancel_lesson(uuid, text)
from public, anon;

grant execute
on function public.cancel_lesson(uuid, text)
to authenticated;

comment on function public.cancel_lesson(uuid, text) is
  'Cancels a canonical right-backed scheduled lesson, restores the same entitlement, and snapshots the canceled lesson schedule on the immutable event. Student cancellation quotas are regular=2 per logical slot/semester and flex=2*floor(base rights/4) per semester; every student re-cancellation of a regular/flex right consumes quota, while academy and carryover cancellations do not.';
