-- ============================================================
-- Forestring v3
-- Student semester plans + logical regular schedule slots
--
-- Calendar date-calculation policy is intentionally NOT handled
-- here. These structures are independent of semester weekday
-- boundaries / closure calculation rules.
-- ============================================================


-- ============================================================
-- 1. STUDENT SEMESTER PLAN STATUS
-- ============================================================

create type public.student_semester_plan_status as enum (
  'planned',
  'active',
  'completed'
);


-- ============================================================
-- 2. STUDENT SEMESTER PLANS
--
-- One row = one student's state for one semester.
--
-- students.student_type remains the CURRENT operational value.
-- student_type_snapshot records the type for this semester.
--
-- For flex:
--   base right count + duration belong here.
--
-- For regular:
--   flex fields remain NULL.
-- ============================================================

create table public.student_semester_plans (
  id uuid primary key
    default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  -- Historical / planned branch snapshot.
  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  student_type_snapshot public.student_type
    not null,

  -- Flex only.
  --
  -- planned flex rows may temporarily have no configuration.
  -- Before activation both values must exist.
  flex_base_right_count integer,

  flex_duration_minutes integer,

  status public.student_semester_plan_status
    not null
    default 'planned',

  created_by uuid
    references public.profiles(id)
    on delete set null,

  updated_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),


  -- One authoritative semester plan per student.
  constraint student_semester_plans_student_semester_unique
    unique (
      student_id,
      semester_id
    ),


  constraint student_semester_plans_flex_count_check
    check (
      flex_base_right_count is null
      or flex_base_right_count > 0
    ),


  -- Duration hard technical rule:
  -- positive and aligned to Forestring's 15-minute grid.
  --
  -- 15 / 30 / 60 are normal defaults,
  -- but privileged staff may later use another 15-minute
  -- multiple after explicit warning.
  constraint student_semester_plans_flex_duration_check
    check (
      flex_duration_minutes is null

      or (
        flex_duration_minutes > 0
        and mod(
          flex_duration_minutes,
          15
        ) = 0
      )
    ),


  -- Count and duration are one configuration unit.
  constraint student_semester_plans_flex_config_pair_check
    check (
      (
        flex_base_right_count is null
        and flex_duration_minutes is null
      )

      or

      (
        flex_base_right_count is not null
        and flex_duration_minutes is not null
      )
    ),


  -- Regular plans never contain flex configuration.
  constraint student_semester_plans_type_config_check
    check (
      student_type_snapshot =
        'flex'::public.student_type

      or (
        flex_base_right_count is null
        and flex_duration_minutes is null
      )
    ),


  -- A flex plan may exist as an incomplete PLANNED draft,
  -- but activation/completion requires its base configuration.
  constraint student_semester_plans_active_flex_config_check
    check (
      student_type_snapshot <>
        'flex'::public.student_type

      or status =
        'planned'::public.student_semester_plan_status

      or (
        flex_base_right_count is not null
        and flex_duration_minutes is not null
      )
    )
);


create index student_semester_plans_student_idx
on public.student_semester_plans (
  student_id,
  semester_id
);


create index student_semester_plans_branch_semester_idx
on public.student_semester_plans (
  branch_id,
  semester_id,
  status
);


create trigger student_semester_plans_set_updated_at
before update
on public.student_semester_plans
for each row
execute function public.set_updated_at();


alter table public.student_semester_plans
enable row level security;


comment on table public.student_semester_plans is
  'Semester-specific student state. students.student_type remains the current operational value; this table stores semester plans/snapshots.';


comment on column public.student_semester_plans.flex_duration_minutes is
  'Flex entitlement duration. Positive 15-minute multiple. 15/30/60 are normal presets, not a database-only allowed set.';


-- ============================================================
-- 3. LOGICAL REGULAR SCHEDULE SLOTS
--
-- Example:
--
-- SLOT-A
--   series v1: teacher A / Tue 18:00 / 30 min
--   series v2: teacher B / Thu 19:00 / 60 min
--
-- Both series versions represent the SAME logical regular
-- entitlement slot.
--
-- Teacher / weekday / time / duration DO NOT belong here.
-- Those belong to lesson_series versions.
-- ============================================================

create table public.regular_schedule_slots (
  id uuid primary key
    default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  -- Historical ownership of this logical slot.
  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  starts_on date not null,

  ends_on date,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint regular_schedule_slots_date_check
    check (
      ends_on is null
      or ends_on >= starts_on
    ),

  -- Required for the composite FK from lesson_series.
  constraint regular_schedule_slots_identity_unique
    unique (
      id,
      student_id,
      branch_id
    )
);


create index regular_schedule_slots_student_idx
on public.regular_schedule_slots (
  student_id,
  starts_on
);


create index regular_schedule_slots_branch_idx
on public.regular_schedule_slots (
  branch_id,
  starts_on
);


create trigger regular_schedule_slots_set_updated_at
before update
on public.regular_schedule_slots
for each row
execute function public.set_updated_at();


alter table public.regular_schedule_slots
enable row level security;


comment on table public.regular_schedule_slots is
  'Logical regular lesson entitlement slots. Schedule details live in versioned lesson_series rows.';


-- ============================================================
-- 4. LINK LESSON SERIES TO LOGICAL SLOT
--
-- Nullable temporarily for existing v3/test series.
--
-- New production regular schedule creation will later go
-- through RPCs that always provide schedule_slot_id.
-- ============================================================

alter table public.lesson_series
add column schedule_slot_id uuid;


alter table public.lesson_series
add constraint lesson_series_schedule_slot_identity_fk
foreign key (
  schedule_slot_id,
  student_id,
  branch_id
)
references public.regular_schedule_slots (
  id,
  student_id,
  branch_id
)
on delete restrict;


create index lesson_series_schedule_slot_idx
on public.lesson_series (
  schedule_slot_id,
  effective_from
)
where schedule_slot_id is not null;


-- ============================================================
-- 5. ONE SCHEDULE VERSION AT A TIME PER LOGICAL SLOT
--
-- A logical slot may have many versions over history,
-- but their effective periods may never overlap.
--
-- v1: ~ 2026-09-14
-- v2: 2026-09-15 ~
-- ============================================================

alter table public.lesson_series
add constraint lesson_series_schedule_slot_no_overlap
exclude using gist (
  schedule_slot_id with =,

  daterange(
    effective_from,

    case
      when effective_until is null then null
      else effective_until + 1
    end,

    '[)'
  ) with &&
)
where (
  schedule_slot_id is not null
);


-- ============================================================
-- 6. TABLE PRIVILEGES
--
-- Direct client writes remain forbidden.
-- Writes will later use trusted RPCs.
-- ============================================================

revoke all
on table
  public.student_semester_plans,
  public.regular_schedule_slots
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table
  public.student_semester_plans,
  public.regular_schedule_slots
from authenticated;


grant select
on table
  public.student_semester_plans,
  public.regular_schedule_slots
to authenticated;


-- ============================================================
-- 7. RLS - SEMESTER PLANS
--
-- master:
--   all
--
-- manager:
--   own branch
--
-- teacher:
--   students with assignment relationship
--
-- student:
--   own
-- ============================================================

create policy student_semester_plans_select
on public.student_semester_plans
for select
to authenticated
using (
  (select private.is_active_user())

  and (

    (select private.is_master())

    or private.manager_has_branch(
      branch_id
    )

    or student_id =
      (select auth.uid())

    or private.teacher_has_student_relation(
      student_id
    )
  )
);


-- ============================================================
-- 8. RLS - REGULAR SCHEDULE SLOTS
-- ============================================================

create policy regular_schedule_slots_select
on public.regular_schedule_slots
for select
to authenticated
using (
  (select private.is_active_user())

  and (

    (select private.is_master())

    or private.manager_has_branch(
      branch_id
    )

    or student_id =
      (select auth.uid())

    or private.teacher_has_student_relation(
      student_id
    )
  )
);