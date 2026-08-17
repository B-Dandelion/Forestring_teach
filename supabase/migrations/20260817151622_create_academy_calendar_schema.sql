-- ============================================================
-- Forestring v3 - Academy calendar schema
-- ============================================================


-- ============================================================
-- SEMESTERS
--
-- Defines academy scheduling periods.
--
-- Example:
-- code:      2026-08
-- starts_on: 2026-08-01
-- ends_on:   2026-08-31
--
-- We intentionally do NOT store a separate status
-- such as current/upcoming/ended.
-- It can be derived from the dates.
-- ============================================================

create table public.semesters (
  id uuid primary key default gen_random_uuid(),

  -- Human-readable identifier.
  -- Example: 2026-08
  code text not null unique,

  starts_on date not null,
  ends_on date not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint semesters_code_not_blank
    check (
      length(btrim(code)) > 0
    ),

  constraint semesters_date_check
    check (
      starts_on <= ends_on
    )
);


create index semesters_starts_on_idx
  on public.semesters(starts_on);


-- Adjacent semesters are allowed:
--
-- 2026-08-01 ~ 2026-08-31
-- 2026-09-01 ~ 2026-09-30
--
-- Overlapping semesters are rejected.
alter table public.semesters
add constraint semesters_no_overlap
exclude using gist (
  daterange(
    starts_on,
    ends_on + 1,
    '[)'
  ) with &&
);


create trigger semesters_set_updated_at
before update on public.semesters
for each row
execute function public.set_updated_at();


-- ============================================================
-- CLOSURE PERIODS
--
-- Academy-wide full-day closure periods.
--
-- This replaces Firestore semester holiday arrays such as:
--   holidayPeriods
--   holidays
--
-- A closure may optionally belong to a semester.
--
-- semester_id = NULL:
--   academy-wide closure not tied to a specific semester.
--
-- For teacher-specific partial-day unavailability,
-- use blocked_periods instead.
-- ============================================================

create table public.closure_periods (
  id uuid primary key default gen_random_uuid(),

  semester_id uuid
    references public.semesters(id)
    on delete set null,

  starts_on date not null,
  ends_on date not null,

  reason text,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint closure_periods_date_check
    check (
      starts_on <= ends_on
    )
);


create index closure_periods_starts_on_idx
  on public.closure_periods(starts_on);

create index closure_periods_semester_idx
  on public.closure_periods(
    semester_id,
    starts_on
  )
  where semester_id is not null;


-- Academy closure periods must not overlap.
--
-- Allowed:
-- 2026-08-10 ~ 2026-08-12
-- 2026-08-13 ~ 2026-08-15
--
-- Rejected:
-- 2026-08-10 ~ 2026-08-14
-- 2026-08-13 ~ 2026-08-15
alter table public.closure_periods
add constraint closure_periods_no_overlap
exclude using gist (
  daterange(
    starts_on,
    ends_on + 1,
    '[)'
  ) with &&
);


-- ============================================================
-- CLOSURE <-> SEMESTER INTEGRITY
--
-- If semester_id is specified, the closure must be fully
-- contained within that semester.
--
-- A closure spanning multiple semesters should instead use
-- semester_id = NULL.
-- ============================================================

create or replace function public.assert_closure_within_semester()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  semester_start date;
  semester_end date;
begin
  if new.semester_id is null then
    return new;
  end if;

  select
    s.starts_on,
    s.ends_on
  into
    semester_start,
    semester_end
  from public.semesters s
  where s.id = new.semester_id;

  if not found then
    raise exception
      'Semester % does not exist.',
      new.semester_id;
  end if;

  if new.starts_on < semester_start
     or new.ends_on > semester_end then
    raise exception
      'Closure period % ~ % must be within semester % ~ %.',
      new.starts_on,
      new.ends_on,
      semester_start,
      semester_end;
  end if;

  return new;
end;
$$;


create trigger closure_periods_assert_semester_range
before insert or update of semester_id, starts_on, ends_on
on public.closure_periods
for each row
execute function public.assert_closure_within_semester();


create trigger closure_periods_set_updated_at
before update on public.closure_periods
for each row
execute function public.set_updated_at();


-- ============================================================
-- ROW LEVEL SECURITY
--
-- Policies will be added in a later migration.
-- Until then, direct Flutter client access remains denied.
-- ============================================================

alter table public.semesters
  enable row level security;

alter table public.closure_periods
  enable row level security;
