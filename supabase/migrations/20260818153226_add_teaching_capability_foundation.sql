-- ============================================================
-- Forestring v3
-- Teaching capability foundation
--
-- profiles.role:
--   authorization scope
--
-- teachers row:
--   person is / has been teaching staff
--
-- teaching_enabled:
--   may currently receive new teaching work
-- ============================================================


alter table public.teachers
add column teaching_enabled boolean
not null
default true;


comment on column public.teachers.teaching_enabled is
  'Whether this teaching staff member can currently receive new assignments, lesson series, lessons, work hours, or blocked periods.';


-- ============================================================
-- NEW TEACHING WORK REQUIRES ENABLED TEACHER
-- ============================================================

create or replace function public.assert_teacher_accepts_new_work()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  current_teaching_enabled boolean;
  current_profile_active boolean;
begin

  select
    t.teaching_enabled,
    p.is_active
  into
    current_teaching_enabled,
    current_profile_active
  from public.teachers t
  join public.profiles p
    on p.id = t.id
  where t.id = new.teacher_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;


  if current_profile_active <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_INACTIVE';
  end if;


  if current_teaching_enabled <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHING_DISABLED';
  end if;


  return new;
end;
$$;


-- Work hours

create trigger
teacher_work_hours_require_enabled_teacher
before insert
or update of teacher_id
on public.teacher_work_hours
for each row
execute function public.assert_teacher_accepts_new_work();


-- One-off blocked periods

create trigger
blocked_periods_require_enabled_teacher
before insert
or update of teacher_id
on public.blocked_periods
for each row
execute function public.assert_teacher_accepts_new_work();


-- Teacher/student assignment

create trigger
teacher_student_assignments_require_enabled_teacher
before insert
or update of teacher_id
on public.teacher_student_assignments
for each row
execute function public.assert_teacher_accepts_new_work();


-- Regular lesson rule

create trigger
lesson_series_require_enabled_teacher
before insert
or update of teacher_id
on public.lesson_series
for each row
execute function public.assert_teacher_accepts_new_work();


-- Actual lesson

create trigger
lessons_require_enabled_teacher
before insert
or update of teacher_id
on public.lessons
for each row
execute function public.assert_teacher_accepts_new_work();


comment on table public.teachers is
  'Teaching staff entity. Teacher-role profiles use this row. Manager-role profiles may also use it when teaching.';
