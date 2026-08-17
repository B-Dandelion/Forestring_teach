-- ============================================================
-- Forestring v3 - Scheduling schema
-- ============================================================


-- ============================================================
-- ENUMS
-- ============================================================

create type public.lesson_type as enum (
  'regular',
  'makeup'
);

create type public.lesson_status as enum (
  'scheduled',
  'canceled'
);


-- ============================================================
-- TEACHER WORK HOURS
--
-- Weekly recurring availability.
--
-- Multiple rows for the same weekday are intentionally allowed.
--
-- Example:
-- Monday 10:00 ~ 13:00
-- Monday 15:00 ~ 19:00
--
-- represents a break from 13:00 ~ 15:00.
-- ============================================================

create table public.teacher_work_hours (
  id uuid primary key default gen_random_uuid(),

  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  -- ISO weekday:
  -- 1 Monday ... 7 Sunday
  weekday smallint not null,

  start_time time not null,
  end_time time not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint teacher_work_hours_weekday_check
    check (
      weekday between 1 and 7
    ),

  constraint teacher_work_hours_time_check
    check (
      start_time < end_time
    ),

  -- Forestring schedules operate at minute precision.
  constraint teacher_work_hours_minute_precision_check
    check (
      extract(second from start_time) = 0
      and extract(second from end_time) = 0
    )
);

create index teacher_work_hours_teacher_weekday_idx
  on public.teacher_work_hours(
    teacher_id,
    weekday,
    start_time
  );


-- Prevent overlapping weekly work-hour segments.
--
-- Allowed:
-- 10:00 ~ 13:00
-- 13:00 ~ 15:00
--
-- Rejected:
-- 10:00 ~ 13:00
-- 12:30 ~ 15:00

alter table public.teacher_work_hours
add constraint teacher_work_hours_no_overlap
exclude using gist (
  teacher_id with =,
  weekday with =,
  int4range(
    (
      extract(hour from start_time)::integer * 60
      + extract(minute from start_time)::integer
    ),
    (
      extract(hour from end_time)::integer * 60
      + extract(minute from end_time)::integer
    ),
    '[)'
  ) with &&
);

create trigger teacher_work_hours_set_updated_at
before update on public.teacher_work_hours
for each row
execute function public.set_updated_at();


-- ============================================================
-- BLOCKED PERIODS
--
-- One-off teacher-specific unavailable periods.
--
-- This replaces Firebase "BanTime" fake booked slots.
-- ============================================================

create table public.blocked_periods (
  id uuid primary key default gen_random_uuid(),

  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  starts_at timestamptz not null,
  ends_at timestamptz not null,

  reason text,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint blocked_periods_time_check
    check (
      starts_at < ends_at
    )
);

create index blocked_periods_teacher_starts_at_idx
  on public.blocked_periods(
    teacher_id,
    starts_at
  );


-- Prevent duplicate / overlapping blocked periods
-- for the same teacher.
alter table public.blocked_periods
add constraint blocked_periods_no_overlap
exclude using gist (
  teacher_id with =,
  tstzrange(
    starts_at,
    ends_at,
    '[)'
  ) with &&
);

create trigger blocked_periods_set_updated_at
before update on public.blocked_periods
for each row
execute function public.set_updated_at();


-- ============================================================
-- LESSON SERIES
--
-- Recurring weekly lesson rule.
--
-- This replaces:
--   students.weeklySchedule[]
--   Firebase lesson code as domain identity
--
-- legacy_code exists ONLY for Firebase migration traceability.
-- ============================================================

create table public.lesson_series (
  id uuid primary key default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  -- ISO weekday:
  -- 1 Monday ... 7 Sunday
  weekday smallint not null,

  start_time time not null,

  duration_minutes integer not null,

  effective_from date not null,
  effective_until date,

  -- Firebase-era weeklySchedule code.
  -- Not used as v3 domain identity.
  legacy_code text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lesson_series_weekday_check
    check (
      weekday between 1 and 7
    ),

  constraint lesson_series_duration_check
    check (
      duration_minutes > 0
      and duration_minutes <= 720
    ),

  constraint lesson_series_minute_precision_check
    check (
      extract(second from start_time) = 0
    ),

  -- Recurring lessons may not cross midnight.
  constraint lesson_series_same_day_check
    check (
      (
        extract(hour from start_time)::integer * 60
        + extract(minute from start_time)::integer
        + duration_minutes
      ) <= 1440
    ),

  constraint lesson_series_effective_date_check
    check (
      effective_until is null
      or effective_until >= effective_from
    ),

  -- Used by lessons composite FK to guarantee that
  -- a regular lesson belongs to the same student/teacher
  -- as its series.
  constraint lesson_series_identity_unique
    unique (
      id,
      student_id,
      teacher_id
    )
);

create index lesson_series_student_idx
  on public.lesson_series(
    student_id,
    effective_from
  );

create index lesson_series_teacher_weekday_idx
  on public.lesson_series(
    teacher_id,
    weekday,
    effective_from
  );

create index lesson_series_legacy_code_idx
  on public.lesson_series(
    student_id,
    legacy_code
  )
  where legacy_code is not null;


-- ============================================================
-- RECURRING SERIES COLLISION PROTECTION
--
-- A student cannot have overlapping recurring lessons
-- during overlapping effective periods.
-- ============================================================

alter table public.lesson_series
add constraint lesson_series_student_no_overlap
exclude using gist (
  student_id with =,

  weekday with =,

  daterange(
    effective_from,
    case
      when effective_until is null then null
      else effective_until + 1
    end,
    '[)'
  ) with &&,

  int4range(
    (
      extract(hour from start_time)::integer * 60
      + extract(minute from start_time)::integer
    ),
    (
      extract(hour from start_time)::integer * 60
      + extract(minute from start_time)::integer
      + duration_minutes
    ),
    '[)'
  ) with &&
);


-- A teacher also cannot have two recurring lesson series
-- occupying the same weekly time during overlapping periods.

alter table public.lesson_series
add constraint lesson_series_teacher_no_overlap
exclude using gist (
  teacher_id with =,

  weekday with =,

  daterange(
    effective_from,
    case
      when effective_until is null then null
      else effective_until + 1
    end,
    '[)'
  ) with &&,

  int4range(
    (
      extract(hour from start_time)::integer * 60
      + extract(minute from start_time)::integer
    ),
    (
      extract(hour from start_time)::integer * 60
      + extract(minute from start_time)::integer
      + duration_minutes
    ),
    '[)'
  ) with &&
);

create trigger lesson_series_set_updated_at
before update on public.lesson_series
for each row
execute function public.set_updated_at();


-- ============================================================
-- LESSON END-TIME FUNCTION
--
-- lessons.ends_at is derived and maintained by PostgreSQL.
-- Flutter must not calculate/store a separate authoritative end time.
-- ============================================================

create or replace function public.set_lesson_ends_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.ends_at :=
    new.starts_at
    + pg_catalog.make_interval(
        mins => new.duration_minutes
      );

  return new;
end;
$$;


-- ============================================================
-- LESSONS
--
-- The ONE canonical source of actual lesson instances.
--
-- We do NOT create:
--   users/{studentId}/lessons copies
--   availableSlots.bookedSlots
--
-- A lesson exists only here.
-- ============================================================

create table public.lessons (
  id uuid primary key default gen_random_uuid(),

  -- NULL only for standalone makeup lessons.
  series_id uuid,

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  teacher_id uuid not null
    references public.teachers(id)
    on delete restrict,

  -- Stable occurrence identity for regular lessons.
  --
  -- Example:
  -- original recurring slot: 2026-08-20 18:00
  -- moved actual lesson:     2026-08-21 19:00
  --
  -- occurrence_at remains 2026-08-20 18:00.
  occurrence_at timestamptz,

  -- Actual current lesson start time.
  starts_at timestamptz not null,

  duration_minutes integer not null,

  -- Derived by set_lesson_ends_at().
  ends_at timestamptz not null,

  lesson_type public.lesson_type not null
    default 'regular',

  status public.lesson_status not null
    default 'scheduled',

  rescheduled_by uuid
    references public.profiles(id)
    on delete set null,

  canceled_by uuid
    references public.profiles(id)
    on delete set null,

  canceled_at timestamptz,

  cancellation_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lessons_duration_check
    check (
      duration_minutes > 0
      and duration_minutes <= 720
    ),

  constraint lessons_time_check
    check (
      starts_at < ends_at
    ),

  -- Regular lessons must belong to a series and have
  -- a stable occurrence identity.
  --
  -- Makeup lessons are standalone.
  constraint lessons_type_series_check
    check (
      (
        lesson_type = 'regular'
        and series_id is not null
        and occurrence_at is not null
      )
      or
      (
        lesson_type = 'makeup'
        and series_id is null
        and occurrence_at is null
      )
    ),

  constraint lessons_cancellation_state_check
    check (
      (
        status = 'scheduled'
        and canceled_at is null
      )
      or
      (
        status = 'canceled'
        and canceled_at is not null
      )
    ),

  -- If series_id exists, ensure this lesson uses the
  -- exact same student and teacher as the lesson series.
  constraint lessons_series_identity_fk
    foreign key (
      series_id,
      student_id,
      teacher_id
    )
    references public.lesson_series(
      id,
      student_id,
      teacher_id
    )
    on delete restrict
);


-- ends_at must be populated BEFORE constraints and
-- collision checks are evaluated.
create trigger lessons_set_ends_at
before insert or update of starts_at, duration_minutes
on public.lessons
for each row
execute function public.set_lesson_ends_at();

create trigger lessons_set_updated_at
before update on public.lessons
for each row
execute function public.set_updated_at();


-- ============================================================
-- LESSON OCCURRENCE UNIQUENESS
--
-- Critical for idempotent future-lesson generation.
--
-- A recurring occurrence can exist only once,
-- even if its actual starts_at is later rescheduled.
-- ============================================================

create unique index lessons_series_occurrence_unique
  on public.lessons(
    series_id,
    occurrence_at
  )
  where series_id is not null;


-- ============================================================
-- ACTUAL LESSON COLLISION PROTECTION
-- ============================================================

-- A teacher cannot have two scheduled lessons at the same time.
alter table public.lessons
add constraint lessons_teacher_no_overlap
exclude using gist (
  teacher_id with =,

  tstzrange(
    starts_at,
    ends_at,
    '[)'
  ) with &&
)
where (
  status = 'scheduled'
);


-- A student cannot have two scheduled lessons at the same time.
alter table public.lessons
add constraint lessons_student_no_overlap
exclude using gist (
  student_id with =,

  tstzrange(
    starts_at,
    ends_at,
    '[)'
  ) with &&
)
where (
  status = 'scheduled'
);


-- ============================================================
-- QUERY INDEXES
-- ============================================================

create index lessons_teacher_starts_at_idx
  on public.lessons(
    teacher_id,
    starts_at
  );

create index lessons_student_starts_at_idx
  on public.lessons(
    student_id,
    starts_at
  );

create index lessons_series_idx
  on public.lessons(
    series_id
  )
  where series_id is not null;

create index lessons_scheduled_teacher_idx
  on public.lessons(
    teacher_id,
    starts_at
  )
  where status = 'scheduled';

create index lessons_scheduled_student_idx
  on public.lessons(
    student_id,
    starts_at
  )
  where status = 'scheduled';


-- ============================================================
-- ROW LEVEL SECURITY
--
-- Policies will be added separately.
-- Until then, Flutter client access remains denied.
-- ============================================================

alter table public.teacher_work_hours
  enable row level security;

alter table public.blocked_periods
  enable row level security;

alter table public.lesson_series
  enable row level security;

alter table public.lessons
  enable row level security;
