create or replace function private.lock_teacher_schedule(
  p_teacher_id uuid
)
returns void
language sql
set search_path = ''
as $$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_teacher_id::text,
      240824
    )
  );
$$;

revoke all
on function private.lock_teacher_schedule(uuid)
from public, anon, authenticated;

create or replace function private.assert_blocked_period_no_lesson_conflict()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.lock_teacher_schedule(new.teacher_id);

  if exists (
    select 1
    from public.lessons l
    where l.teacher_id = new.teacher_id
      and l.status = 'scheduled'::public.lesson_status
      and tstzrange(l.starts_at, l.ends_at, '[)')
          && tstzrange(new.starts_at, new.ends_at, '[)')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BLOCKED_PERIOD_LESSON_CONFLICT';
  end if;

  return new;
end;
$$;

create or replace function private.assert_lesson_no_blocked_period_conflict()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_ends_at timestamptz;
begin
  if new.status <> 'scheduled'::public.lesson_status then
    return new;
  end if;

  perform private.lock_teacher_schedule(new.teacher_id);

  v_ends_at :=
    new.starts_at
    + pg_catalog.make_interval(mins => new.duration_minutes);

  if exists (
    select 1
    from public.blocked_periods bp
    where bp.teacher_id = new.teacher_id
      and tstzrange(bp.starts_at, bp.ends_at, '[)')
          && tstzrange(new.starts_at, v_ends_at, '[)')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_BLOCKED_PERIOD_CONFLICT';
  end if;

  return new;
end;
$$;

revoke all
on function private.assert_blocked_period_no_lesson_conflict()
from public, anon, authenticated;

revoke all
on function private.assert_lesson_no_blocked_period_conflict()
from public, anon, authenticated;

drop trigger if exists
  blocked_periods_prevent_lesson_overlap
on public.blocked_periods;

create trigger
  blocked_periods_prevent_lesson_overlap
before insert or update of
  teacher_id,
  starts_at,
  ends_at
on public.blocked_periods
for each row
execute function
  private.assert_blocked_period_no_lesson_conflict();

drop trigger if exists
  zz_lessons_prevent_blocked_period_overlap
on public.lessons;

create trigger
  zz_lessons_prevent_blocked_period_overlap
before insert or update of
  teacher_id,
  starts_at,
  duration_minutes,
  status
on public.lessons
for each row
execute function
  private.assert_lesson_no_blocked_period_conflict();

comment on function private.lock_teacher_schedule(uuid) is
  'Serializes lesson and personal-schedule writes for one teacher.';

comment on function private.assert_blocked_period_no_lesson_conflict() is
  'Rejects a teacher personal schedule that overlaps a scheduled lesson.';

comment on function private.assert_lesson_no_blocked_period_conflict() is
  'Rejects a scheduled lesson that overlaps a teacher personal schedule.';
