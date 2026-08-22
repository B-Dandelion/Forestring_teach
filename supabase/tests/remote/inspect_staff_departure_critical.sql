-- ============================================================
-- Forestring v3
-- Staff departure critical preflight
-- READ ONLY
-- ============================================================


-- 1. CURRENT COLUMNS
select
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'profiles',
    'teachers'
  )
order by
  table_name,
  ordinal_position;


-- 2. TRIGGERS THAT COULD ENFORCE DEPARTURE GUARDS
select
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true)
    as trigger_definition
from pg_trigger t
join pg_class c
  on c.oid = t.tgrelid
join pg_namespace n
  on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in (
    'teachers',
    'teacher_student_assignments',
    'lesson_series',
    'lessons'
  )
order by
  c.relname,
  t.tgname;


-- 3. ASSIGN STUDENT TEACHER
select
  pg_get_functiondef(p.oid)
    as assign_student_teacher_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'assign_student_teacher';


-- 4. CHANGE STUDENT TEACHER
select
  pg_get_functiondef(p.oid)
    as change_student_teacher_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'change_student_teacher';


-- 5. ASSIGNABLE TEACHERS
select
  pg_get_functiondef(p.oid)
    as get_assignable_teachers_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname =
      'get_assignable_teachers_for_student';


-- 6. REGULAR SCHEDULE CHANGE
select
  pg_get_functiondef(p.oid)
    as change_regular_schedule_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname =
      'change_regular_schedule';


-- 7. AVAILABILITY CANDIDATES
select
  pg_get_functiondef(p.oid)
    as lesson_right_slot_candidates_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'private'
  and p.proname =
      'lesson_right_slot_candidates';


-- 8. CURRENT STAFF ROLE CHANGE
select
  pg_get_functiondef(p.oid)
    as change_staff_role_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname =
      'change_staff_role';
