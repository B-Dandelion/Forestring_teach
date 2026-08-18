-- ============================================================
-- Forestring v3
-- Branch + manager/student-type foundation
-- ============================================================


-- ============================================================
-- ROLE
-- ============================================================

alter type public.user_role
add value if not exists 'manager'
after 'master';


-- ============================================================
-- STUDENT TYPE
--
-- regular:
--   recurring regular schedule exists
--   lesson_series allowed
--
-- flex:
--   no recurring schedule
--   lesson credits / one-off booking only
-- ============================================================

create type public.student_type as enum (
  'regular',
  'flex'
);


-- ============================================================
-- BRANCHES
-- ============================================================

create table public.branches (
  id uuid primary key
    default gen_random_uuid(),

  name text not null,

  is_active boolean not null
    default true,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint branches_name_not_blank
    check (
      length(btrim(name)) > 0
    )
);


-- Case-insensitive unique branch names.
create unique index branches_name_unique_idx
on public.branches (
  lower(btrim(name))
);


create trigger branches_set_updated_at
before update
on public.branches
for each row
execute function public.set_updated_at();


alter table public.branches
enable row level security;


-- ============================================================
-- CURRENT BRANCH MEMBERSHIP
--
-- profiles.branch_id is the ONE current branch membership source.
--
-- master:
--   normally NULL
--
-- manager / teacher / student:
--   branch assigned after branch data is migrated.
--
-- Nullable temporarily because existing v3 test accounts do not
-- yet have real branch assignments.
-- ============================================================

alter table public.profiles
add column branch_id uuid
references public.branches(id)
on delete restrict;


create index profiles_branch_role_idx
on public.profiles (
  branch_id,
  role
);


-- ============================================================
-- STUDENT CLASSIFICATION
-- ============================================================

alter table public.students
add column student_type public.student_type
not null
default 'regular';


create index students_type_status_idx
on public.students (
  student_type,
  status
);


-- ============================================================
-- HISTORICAL BRANCH OWNERSHIP
--
-- These rows preserve the branch at the time of the operation.
-- A future profile branch transfer must not rewrite history.
--
-- Nullable only during the migration/backfill phase.
-- Future RPCs/triggers will always populate these.
-- ============================================================

alter table public.teacher_student_assignments
add column branch_id uuid
references public.branches(id)
on delete restrict;


alter table public.lesson_series
add column branch_id uuid
references public.branches(id)
on delete restrict;


alter table public.lessons
add column branch_id uuid
references public.branches(id)
on delete restrict;


alter table public.lesson_rebooking_credits
add column branch_id uuid
references public.branches(id)
on delete restrict;


create index teacher_student_assignments_branch_idx
on public.teacher_student_assignments (
  branch_id,
  starts_on
);


create index lesson_series_branch_idx
on public.lesson_series (
  branch_id,
  effective_from
);


create index lessons_branch_starts_at_idx
on public.lessons (
  branch_id,
  starts_at
);


create index lesson_rebooking_credits_branch_status_idx
on public.lesson_rebooking_credits (
  branch_id,
  status
);


comment on column public.profiles.branch_id is
  'Current branch membership. Transitional nullable until legacy data backfill is complete.';

comment on column public.students.student_type is
  'regular = recurring lesson series, flex = no recurring schedule / credit-based booking.';

comment on column public.lessons.branch_id is
  'Historical branch owning this lesson. Must not change merely because a profile later transfers branches.';
