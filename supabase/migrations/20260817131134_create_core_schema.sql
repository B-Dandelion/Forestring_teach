-- ============================================================
-- Forestring v3 - Core schema
-- ============================================================

-- Used to prevent overlapping teacher assignment periods.
create extension if not exists btree_gist
with schema extensions;


-- ============================================================
-- ENUMS
-- ============================================================

create type public.user_role as enum (
  'master',
  'teacher',
  'student'
);

create type public.student_status as enum (
  'active',
  'withdrawn'
);


-- ============================================================
-- COMMON FUNCTIONS
-- ============================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ============================================================
-- PROFILES
-- Supabase Auth identity <-> Forestring user profile
-- ============================================================

create table public.profiles (
  id uuid primary key
    references auth.users(id)
    on delete cascade,

  -- Firebase-era ID such as TCH_..., STU_...
  -- Used only for migration / traceability.
  legacy_id text unique,

  -- Duplicate display names are intentionally allowed.
  display_name text not null,

  role public.user_role not null,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_display_name_not_blank
    check (length(btrim(display_name)) > 0)
);

create index profiles_display_name_idx
  on public.profiles(display_name);

create index profiles_role_idx
  on public.profiles(role);

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();


-- ============================================================
-- TEACHERS
-- Teacher-specific entity
-- ============================================================

create table public.teachers (
  id uuid primary key
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger teachers_set_updated_at
before update on public.teachers
for each row
execute function public.set_updated_at();


-- ============================================================
-- STUDENTS
-- Student-specific entity
-- ============================================================

create table public.students (
  id uuid primary key
    references public.profiles(id)
    on delete cascade,

  status public.student_status not null default 'active',

  withdrawal_date date,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint students_withdrawal_state_check
    check (
      (
        status = 'active'
        and withdrawal_date is null
      )
      or
      (
        status = 'withdrawn'
        and withdrawal_date is not null
      )
    )
);

create index students_status_idx
  on public.students(status);

create trigger students_set_updated_at
before update on public.students
for each row
execute function public.set_updated_at();


-- ============================================================
-- PROFILE ROLE INTEGRITY
-- Prevent a student profile from being inserted into teachers,
-- or a teacher profile from being inserted into students.
-- ============================================================

create or replace function public.assert_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  expected_role public.user_role;
  actual_role public.user_role;
begin
  expected_role := tg_argv[0]::public.user_role;

  select p.role
  into actual_role
  from public.profiles p
  where p.id = new.id;

  if not found then
    raise exception 'Profile % does not exist.', new.id;
  end if;

  if actual_role <> expected_role then
    raise exception
      'Profile % has role %, expected %.',
      new.id,
      actual_role,
      expected_role;
  end if;

  return new;
end;
$$;

create trigger teachers_assert_profile_role
before insert or update of id
on public.teachers
for each row
execute function public.assert_profile_role('teacher');

create trigger students_assert_profile_role
before insert or update of id
on public.students
for each row
execute function public.assert_profile_role('student');


-- ============================================================
-- TEACHER <-> STUDENT ASSIGNMENT HISTORY
--
-- Example:
-- A teacher: 2026-01-01 ~ 2026-07-31
-- B teacher: 2026-08-01 ~ null
--
-- We do NOT store:
--   students.teacher_id
--   teachers.student_ids[]
-- ============================================================

create table public.teacher_student_assignments (
  id uuid primary key default gen_random_uuid(),

  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  starts_on date not null,
  ends_on date,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint teacher_student_assignments_date_check
    check (
      ends_on is null
      or ends_on >= starts_on
    )
);

create index teacher_student_assignments_teacher_idx
  on public.teacher_student_assignments(
    teacher_id,
    starts_on
  );

create index teacher_student_assignments_student_idx
  on public.teacher_student_assignments(
    student_id,
    starts_on
  );

-- A student cannot belong to two teachers during overlapping periods.
--
-- daterange uses:
--   starts_on = inclusive
--   ends_on + 1 day = exclusive
--
-- ends_on NULL means an open-ended assignment.
alter table public.teacher_student_assignments
add constraint teacher_student_assignments_no_overlap
exclude using gist (
  student_id with =,
  daterange(
    starts_on,
    case
      when ends_on is null then null
      else ends_on + 1
    end,
    '[)'
  ) with &&
);

create trigger teacher_student_assignments_set_updated_at
before update on public.teacher_student_assignments
for each row
execute function public.set_updated_at();


-- ============================================================
-- ROW LEVEL SECURITY
--
-- Policies are intentionally added in a later migration.
-- Until then, client-side access to these tables is denied.
-- ============================================================

alter table public.profiles
  enable row level security;

alter table public.teachers
  enable row level security;

alter table public.students
  enable row level security;

alter table public.teacher_student_assignments
  enable row level security;
