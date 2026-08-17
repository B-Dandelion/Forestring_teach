-- ============================================================
-- Forestring v3 - Row Level Security policies
--
-- Direct Flutter access:
--   SELECT                  allowed according to role
--   INSERT/UPDATE/DELETE    denied
--
-- Writes will later go through trusted database RPCs.
-- ============================================================


-- ============================================================
-- RLS HELPER FUNCTIONS
--
-- These live in the private schema so they are not exposed as
-- normal Data API endpoints.
--
-- SECURITY DEFINER avoids RLS recursion when a policy needs to
-- inspect profiles or assignment tables.
-- ============================================================

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
  );
$$;


create or replace function private.is_master()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and p.role = 'master'::public.user_role
  );
$$;


-- Teacher may see students with whom they have an assignment
-- relationship.
--
-- We intentionally allow historical assignment relationships
-- here so past lesson/student history remains accessible.
create or replace function private.teacher_has_student_relation(
  p_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teacher_student_assignments a
    where a.teacher_id = (select auth.uid())
      and a.student_id = p_student_id
  );
$$;


-- Student may see the profile of a teacher who has been assigned
-- to them. Useful later for the student app without making every
-- teacher profile globally visible.
create or replace function private.student_has_teacher_relation(
  p_teacher_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = (select auth.uid())
      and a.teacher_id = p_teacher_id
  );
$$;


-- ============================================================
-- HELPER FUNCTION PERMISSIONS
-- ============================================================

-- private is still not an exposed Data API schema.
-- authenticated only receives enough permission for RLS policies
-- to execute these helpers.

grant usage on schema private
to authenticated;

revoke all
on function private.is_active_user()
from public, anon;

revoke all
on function private.is_master()
from public, anon;

revoke all
on function private.teacher_has_student_relation(uuid)
from public, anon;

revoke all
on function private.student_has_teacher_relation(uuid)
from public, anon;

grant execute
on function private.is_active_user()
to authenticated;

grant execute
on function private.is_master()
to authenticated;

grant execute
on function private.teacher_has_student_relation(uuid)
to authenticated;

grant execute
on function private.student_has_teacher_relation(uuid)
to authenticated;


-- ============================================================
-- TABLE PRIVILEGES
--
-- anon:
--   no direct access
--
-- authenticated:
--   SELECT only
--
-- All direct writes remain denied.
-- ============================================================

revoke all
on table
  public.profiles,
  public.teachers,
  public.students,
  public.teacher_student_assignments,
  public.teacher_work_hours,
  public.blocked_periods,
  public.lesson_series,
  public.lessons,
  public.semesters,
  public.closure_periods
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table
  public.profiles,
  public.teachers,
  public.students,
  public.teacher_student_assignments,
  public.teacher_work_hours,
  public.blocked_periods,
  public.lesson_series,
  public.lessons,
  public.semesters,
  public.closure_periods
from authenticated;


grant select
on table
  public.profiles,
  public.teachers,
  public.students,
  public.teacher_student_assignments,
  public.teacher_work_hours,
  public.blocked_periods,
  public.lesson_series,
  public.lessons,
  public.semesters,
  public.closure_periods
to authenticated;


-- ============================================================
-- PROFILES
--
-- master:
--   all profiles
--
-- teacher:
--   own profile
--   profiles of students they have taught
--
-- student:
--   own profile
--   profiles of assigned teachers
-- ============================================================

drop policy if exists profiles_select
on public.profiles;

create policy profiles_select
on public.profiles
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or id = (select auth.uid())

    or (
      role = 'student'::public.user_role
      and private.teacher_has_student_relation(id)
    )

    or (
      role = 'teacher'::public.user_role
      and private.student_has_teacher_relation(id)
    )
  )
);


-- ============================================================
-- TEACHERS
--
-- master:
--   all
--
-- teacher:
--   own teacher row
-- ============================================================

drop policy if exists teachers_select
on public.teachers;

create policy teachers_select
on public.teachers
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())
    or id = (select auth.uid())
  )
);


-- ============================================================
-- STUDENTS
--
-- master:
--   all
--
-- teacher:
--   students with an assignment relationship
--
-- student:
--   own row
-- ============================================================

drop policy if exists students_select
on public.students;

create policy students_select
on public.students
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or id = (select auth.uid())

    or private.teacher_has_student_relation(id)
  )
);


-- ============================================================
-- TEACHER / STUDENT ASSIGNMENTS
-- ============================================================

drop policy if exists teacher_student_assignments_select
on public.teacher_student_assignments;

create policy teacher_student_assignments_select
on public.teacher_student_assignments
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- TEACHER WORK HOURS
--
-- Direct read is currently restricted to:
--   master
--   owning teacher
--
-- Student-side availability will later use a safe availability
-- RPC rather than exposing internal scheduling data directly.
-- ============================================================

drop policy if exists teacher_work_hours_select
on public.teacher_work_hours;

create policy teacher_work_hours_select
on public.teacher_work_hours
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())
    or teacher_id = (select auth.uid())
  )
);


-- ============================================================
-- BLOCKED PERIODS
--
-- Reasons for blocks may be internal, so students do not receive
-- direct table access.
-- ============================================================

drop policy if exists blocked_periods_select
on public.blocked_periods;

create policy blocked_periods_select
on public.blocked_periods
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())
    or teacher_id = (select auth.uid())
  )
);


-- ============================================================
-- LESSON SERIES
-- ============================================================

drop policy if exists lesson_series_select
on public.lesson_series;

create policy lesson_series_select
on public.lesson_series
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- LESSONS
-- ============================================================

drop policy if exists lessons_select
on public.lessons;

create policy lessons_select
on public.lessons
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- SEMESTERS
--
-- Academy calendar information is readable by every active,
-- authenticated Forestring user.
-- ============================================================

drop policy if exists semesters_select
on public.semesters;

create policy semesters_select
on public.semesters
for select
to authenticated
using (
  (select private.is_active_user())
);


-- ============================================================
-- CLOSURE PERIODS
-- ============================================================

drop policy if exists closure_periods_select
on public.closure_periods;

create policy closure_periods_select
on public.closure_periods
for select
to authenticated
using (
  (select private.is_active_user())
);
