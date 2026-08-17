-- ============================================================
-- Forestring v3 - Lesson rebooking credits
--
-- A credit represents the right created when a student
-- successfully cancels one regular lesson.
--
-- Business rules:
--
-- 1. Each lesson series may be canceled by the student
--    at most twice per semester.
--
-- 2. One successful student cancellation creates one credit.
--
-- 3. A credit may be consumed once to rebook that lesson.
--
-- 4. At most one unused credit per student may be carried
--    into the next semester.
--
-- 5. A carried credit may never be carried again.
-- ============================================================


-- ============================================================
-- ENUM
-- ============================================================

create type public.rebooking_credit_status as enum (
  'available',
  'consumed',
  'expired'
);


-- ============================================================
-- TABLE
-- ============================================================

create table public.lesson_rebooking_credits (
  id uuid primary key default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  -- The lesson whose cancellation created this credit.
  source_lesson_id uuid not null unique
    references public.lessons(id)
    on delete restrict,

  -- The recurring schedule this cancellation belongs to.
  source_series_id uuid not null
    references public.lesson_series(id)
    on delete restrict,

  -- Semester in which the original cancellation occurred.
  source_semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  -- Semester in which this credit may currently be used.
  --
  -- Initially:
  --   usable_semester_id = source_semester_id
  --
  -- After one carry-over:
  --   usable_semester_id = next semester
  usable_semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  -- Snapshot of the teacher / duration at the moment the
  -- cancellation created this right.
  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  duration_minutes integer not null,

  -- 1 or 2 within:
  --
  --   source_series_id + source_semester_id
  --
  -- This makes the "maximum two cancellations per series
  -- per semester" rule structurally enforceable.
  cancellation_no smallint not null,

  status public.rebooking_credit_status
    not null
    default 'available',

  -- 0 = never carried
  -- 1 = carried exactly once
  --
  -- No value above 1 is allowed.
  carryover_count smallint
    not null
    default 0,

  carried_over_at timestamptz,

  consumed_at timestamptz,

  -- In the current design we reuse the same lesson occurrence
  -- when the credit is consumed.
  --
  -- This field records the actual new start time for audit
  -- without requiring another lesson copy.
  consumed_starts_at timestamptz,

  issued_at timestamptz
    not null
    default now(),

  expires_at timestamptz,

  created_at timestamptz
    not null
    default now(),

  updated_at timestamptz
    not null
    default now(),


  constraint lesson_rebooking_credits_duration_check
    check (
      duration_minutes > 0
      and duration_minutes <= 720
    ),

  constraint lesson_rebooking_credits_cancellation_no_check
    check (
      cancellation_no between 1 and 2
    ),

  constraint lesson_rebooking_credits_carryover_check
    check (
      carryover_count between 0 and 1
    ),

  constraint lesson_rebooking_credits_carryover_state_check
    check (
      (
        carryover_count = 0
        and carried_over_at is null
      )
      or
      (
        carryover_count = 1
        and carried_over_at is not null
      )
    ),

  constraint lesson_rebooking_credits_consumption_state_check
    check (
      (
        status = 'consumed'
        and consumed_at is not null
        and consumed_starts_at is not null
      )
      or
      (
        status <> 'consumed'
        and consumed_at is null
        and consumed_starts_at is null
      )
    )
);


-- ============================================================
-- MAXIMUM TWO STUDENT CANCELLATIONS
--
-- Example:
--
-- Tuesday series / August:
--   cancellation_no = 1
--   cancellation_no = 2
--
-- A third row is structurally impossible.
--
-- Wednesday series is counted independently.
-- ============================================================

alter table public.lesson_rebooking_credits
add constraint lesson_rebooking_credits_series_cancel_unique
unique (
  source_series_id,
  source_semester_id,
  cancellation_no
);


-- ============================================================
-- ONE CARRIED CREDIT PER STUDENT / TARGET SEMESTER
--
-- A student may have many normal current-semester credits,
-- but only one available carried-over credit for a semester.
-- ============================================================

create unique index lesson_rebooking_credits_one_carryover_idx
  on public.lesson_rebooking_credits(
    student_id,
    usable_semester_id
  )
  where (
    status = 'available'
    and carryover_count = 1
  );


-- ============================================================
-- QUERY INDEXES
-- ============================================================

create index lesson_rebooking_credits_student_status_idx
  on public.lesson_rebooking_credits(
    student_id,
    status,
    usable_semester_id
  );

create index lesson_rebooking_credits_series_semester_idx
  on public.lesson_rebooking_credits(
    source_series_id,
    source_semester_id
  );

create index lesson_rebooking_credits_teacher_idx
  on public.lesson_rebooking_credits(
    teacher_id,
    status
  );


-- ============================================================
-- UPDATED_AT
-- ============================================================

create trigger lesson_rebooking_credits_set_updated_at
before update on public.lesson_rebooking_credits
for each row
execute function public.set_updated_at();


-- ============================================================
-- ROW LEVEL SECURITY
--
-- Direct writes remain forbidden.
--
-- master:
--   all credits
--
-- teacher:
--   credits belonging to students with whom the teacher has
--   an assignment relationship
--
-- student:
--   own credits
-- ============================================================

alter table public.lesson_rebooking_credits
  enable row level security;


revoke all
on table public.lesson_rebooking_credits
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table public.lesson_rebooking_credits
from authenticated;


grant select
on table public.lesson_rebooking_credits
to authenticated;


create policy lesson_rebooking_credits_select
on public.lesson_rebooking_credits
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or student_id = (select auth.uid())

    or private.teacher_has_student_relation(student_id)
  )
);
