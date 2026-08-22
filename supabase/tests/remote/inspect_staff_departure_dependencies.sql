-- ============================================================
-- Forestring v3
-- Staff departure lifecycle preflight
-- READ ONLY
-- ============================================================


-- ============================================================
-- 1. RELEVANT TABLE COLUMNS
-- ============================================================

select
  table_schema,
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable
from information_schema.columns
where table_schema in ('public', 'private')
  and table_name in (
    'profiles',
    'teachers',
    'teacher_student_assignments',
    'lesson_series',
    'lessons',
    'regular_schedule_slots',
    'teacher_work_hours',
    'blocked_periods'
  )
order by
  table_schema,
  table_name,
  ordinal_position;


-- ============================================================
-- 2. EXISTING TRIGGERS
-- ============================================================

select
  n.nspname as schema_name,
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c
  on c.oid = t.tgrelid
join pg_namespace n
  on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in (
    'profiles',
    'teachers',
    'teacher_student_assignments',
    'lesson_series',
    'lessons'
  )
order by
  c.relname,
  t.tgname;


-- ============================================================
-- 3. FUNCTION SIGNATURES / SECURITY STYLE
-- ============================================================

select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid)
    as identity_arguments,
  pg_get_function_result(p.oid)
    as result_type,
  p.prosecdef as security_definer
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where (
  n.nspname = 'public'
  and p.proname in (
    'change_staff_role',
    'assign_student_teacher',
    'change_student_teacher',
    'get_assignable_teachers_for_student',
    'change_regular_schedule',
    'update_lesson_once',
    'book_lesson_right',
    'activate_student_semester_plan'
  )
)
or (
  n.nspname = 'private'
  and p.proname in (
    'lesson_right_slot_candidates',
    'student_type_on_date'
  )
)
order by
  n.nspname,
  p.proname;


-- ============================================================
-- 4. CRITICAL FUNCTION DEFINITIONS
--
-- These are the functions most likely to need a patch after
-- staff departure foundation is added.
-- ============================================================

select
  '===== change_staff_role =====' as section,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'change_staff_role';

select
  '===== change_student_teacher =====' as section,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'change_student_teacher';

select
  '===== get_assignable_teachers_for_student =====' as section,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_assignable_teachers_for_student';

select
  '===== lesson_right_slot_candidates =====' as section,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'private'
  and p.proname = 'lesson_right_slot_candidates';


-- ============================================================
-- 5. FK / CHECK / EXCLUSION CONSTRAINTS
-- ============================================================

select
  n.nspname as schema_name,
  c.relname as table_name,
  con.conname as constraint_name,
  pg_get_constraintdef(con.oid, true)
    as constraint_definition
from pg_constraint con
join pg_class c
  on c.oid = con.conrelid
join pg_namespace n
  on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'teachers',
    'teacher_student_assignments',
    'lesson_series',
    'lessons'
  )
order by
  c.relname,
  con.conname;
