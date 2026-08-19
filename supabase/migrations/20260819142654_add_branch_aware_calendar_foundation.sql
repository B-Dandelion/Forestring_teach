-- ============================================================
-- Forestring v3
-- Branch-aware academy calendar foundation
--
-- Global semesters are defaults.
-- A branch stores a semester override ONLY when it differs.
--
-- Weekday boundary itself is intentionally NOT hard-coded yet.
-- ============================================================


-- ============================================================
-- 1. GLOBAL SEMESTER WEEK STRUCTURE
--
-- Existing rows are not validated yet because current hosted
-- data may contain temporary/test calendar rows.
--
-- New/updated rows must:
--   - contain at least 28 inclusive days
--   - contain a whole number of 7-day weeks
-- ============================================================

alter table public.semesters
add constraint semesters_week_structure_check
check (
  (ends_on - starts_on + 1) >= 28
  and
  mod(
    ends_on - starts_on + 1,
    7
  ) = 0
)
not valid;


comment on table public.semesters is
  'Global/default academy semesters. Branches inherit these dates unless an explicit branch_semester_overrides row exists.';


-- ============================================================
-- 2. BRANCH SEMESTER OVERRIDES
--
-- No row:
--   branch uses global semester dates.
--
-- Row exists:
--   branch uses the complete start/end range below.
--
-- We store BOTH dates, rather than nullable per-field overrides,
-- so one override always represents one complete effective range.
-- ============================================================

create table public.branch_semester_overrides (
  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  starts_on date not null,
  ends_on date not null,

  updated_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  primary key (
    branch_id,
    semester_id
  ),

  constraint branch_semester_overrides_date_check
    check (
      starts_on <= ends_on
    ),

  constraint branch_semester_overrides_week_structure_check
    check (
      (ends_on - starts_on + 1) >= 28
      and
      mod(
        ends_on - starts_on + 1,
        7
      ) = 0
    )
);


create index branch_semester_overrides_semester_idx
on public.branch_semester_overrides (
  semester_id,
  branch_id
);


create trigger branch_semester_overrides_set_updated_at
before update
on public.branch_semester_overrides
for each row
execute function public.set_updated_at();


alter table public.branch_semester_overrides
enable row level security;


-- ============================================================
-- 3. DO NOT STORE REDUNDANT OVERRIDES
--
-- The absence of an override row must mean:
-- "this branch follows the global default."
--
-- This makes the future master UI able to show only changed
-- branches without comparing every record manually.
-- ============================================================

create or replace function public.assert_semester_override_differs()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_default_start date;
  v_default_end date;
begin

  select
    s.starts_on,
    s.ends_on
  into
    v_default_start,
    v_default_end
  from public.semesters s
  where s.id = new.semester_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;


  if new.starts_on = v_default_start
     and new.ends_on = v_default_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REDUNDANT_SEMESTER_OVERRIDE';

  end if;


  return new;
end;
$$;


create trigger branch_semester_overrides_assert_difference
before insert
or update of semester_id, starts_on, ends_on
on public.branch_semester_overrides
for each row
execute function public.assert_semester_override_differs();


-- ============================================================
-- 4. EFFECTIVE SEMESTER HELPER
--
-- One source for all future:
--   lesson materialization
--   cancellation
--   carryover
--   closure validation
--   semester activation
-- ============================================================

create or replace function private.get_effective_semester_bounds(
  p_branch_id uuid,
  p_semester_id uuid
)
returns table (
  starts_on date,
  ends_on date,
  is_overridden boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(
      o.starts_on,
      s.starts_on
    ) as starts_on,

    coalesce(
      o.ends_on,
      s.ends_on
    ) as ends_on,

    (o.branch_id is not null)
      as is_overridden

  from public.semesters s

  left join public.branch_semester_overrides o
    on o.semester_id = s.id
    and o.branch_id = p_branch_id

  where s.id = p_semester_id;
$$;


revoke all
on function private.get_effective_semester_bounds(
  uuid,
  uuid
)
from public, anon, authenticated;


-- ============================================================
-- 5. CLOSURE TYPES
--
-- ordinary:
--   day/partial-period closure
--   DOES NOT reduce instructional-week count
--
-- instructional_break:
--   official whole-week-equivalent academy break
--   duration must be 7, 14, 21... inclusive days
-- ============================================================

create type public.closure_kind as enum (
  'ordinary',
  'instructional_break'
);


alter table public.closure_periods
add column branch_id uuid
references public.branches(id)
on delete restrict;


alter table public.closure_periods
add column closure_kind public.closure_kind
not null
default 'ordinary';


-- The old exclusion constraint was academy-global.
-- Closures are now independent per branch.

alter table public.closure_periods
drop constraint if exists closure_periods_no_overlap;


-- ============================================================
-- 6. PRESERVE EXISTING GLOBAL CLOSURES
--
-- Existing global closure rows represented "every branch".
-- Copy them once per existing branch before making branch_id
-- mandatory.
-- ============================================================

do $$
begin

  if exists (
    select 1
    from public.closure_periods
    where branch_id is null
  )
  and not exists (
    select 1
    from public.branches
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CLOSURE_MIGRATION_REQUIRES_BRANCH';

  end if;

end;
$$;


insert into public.closure_periods (
  id,
  semester_id,
  starts_on,
  ends_on,
  reason,
  created_by,
  created_at,
  updated_at,
  branch_id,
  closure_kind
)
select
  gen_random_uuid(),
  cp.semester_id,
  cp.starts_on,
  cp.ends_on,
  cp.reason,
  cp.created_by,
  cp.created_at,
  cp.updated_at,
  b.id,
  cp.closure_kind
from public.closure_periods cp
cross join public.branches b
where cp.branch_id is null;


delete from public.closure_periods
where branch_id is null;


alter table public.closure_periods
alter column branch_id set not null;


-- ============================================================
-- 7. BRANCH-SCOPED CLOSURE CONSTRAINTS
-- ============================================================

alter table public.closure_periods
add constraint closure_periods_instructional_break_check
check (
  closure_kind <>
    'instructional_break'::public.closure_kind

  or

  (
    semester_id is not null

    and
    (ends_on - starts_on + 1) >= 7

    and
    mod(
      ends_on - starts_on + 1,
      7
    ) = 0
  )
);


alter table public.closure_periods
add constraint closure_periods_branch_no_overlap
exclude using gist (
  branch_id with =,

  daterange(
    starts_on,
    ends_on + 1,
    '[)'
  ) with &&
);


create index closure_periods_branch_date_idx
on public.closure_periods (
  branch_id,
  starts_on
);


create index closure_periods_branch_semester_idx
on public.closure_periods (
  branch_id,
  semester_id,
  starts_on
)
where semester_id is not null;


-- ============================================================
-- 8. CLOSURE MUST FIT THE BRANCH'S EFFECTIVE SEMESTER
-- ============================================================

create or replace function public.assert_closure_within_semester()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_semester_start date;
  v_semester_end date;
begin

  if new.semester_id is null then

    if new.closure_kind =
       'instructional_break'::public.closure_kind then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_INSTRUCTIONAL_BREAK_REQUIRES_SEMESTER';

    end if;

    return new;
  end if;


  select
    effective.starts_on,
    effective.ends_on
  into
    v_semester_start,
    v_semester_end
  from private.get_effective_semester_bounds(
    new.branch_id,
    new.semester_id
  ) effective;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_FOUND';
  end if;


  if new.starts_on < v_semester_start
     or new.ends_on > v_semester_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';

  end if;


  return new;
end;
$$;


drop trigger if exists
  closure_periods_assert_semester_range
on public.closure_periods;


create trigger closure_periods_assert_semester_range
before insert
or update of
  branch_id,
  semester_id,
  starts_on,
  ends_on,
  closure_kind
on public.closure_periods
for each row
execute function public.assert_closure_within_semester();


-- ============================================================
-- 9. SEMESTER INSTRUCTIONAL-WEEK CALCULATOR
--
-- Core rule:
--
-- total weeks
-- - instructional break weeks
-- = teaching weeks
--
-- Final valid semester target = exactly 4 teaching weeks.
--
-- Ordinary closures are intentionally ignored here.
-- ============================================================

create or replace function private.get_semester_week_summary(
  p_branch_id uuid,
  p_semester_id uuid
)
returns table (
  effective_starts_on date,
  effective_ends_on date,
  total_days integer,
  total_weeks integer,
  instructional_break_days integer,
  instructional_break_weeks integer,
  teaching_weeks integer,
  has_four_teaching_weeks boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with effective as (
    select
      e.starts_on,
      e.ends_on
    from private.get_effective_semester_bounds(
      p_branch_id,
      p_semester_id
    ) e
  ),

  break_summary as (
    select
      coalesce(
        sum(
          cp.ends_on
          - cp.starts_on
          + 1
        ),
        0
      )::integer
        as break_days

    from public.closure_periods cp

    where cp.branch_id =
          p_branch_id

      and cp.semester_id =
          p_semester_id

      and cp.closure_kind =
          'instructional_break'
            ::public.closure_kind
  )

  select
    e.starts_on,

    e.ends_on,

    (
      e.ends_on
      - e.starts_on
      + 1
    )::integer
      as total_days,

    (
      (
        e.ends_on
        - e.starts_on
        + 1
      ) / 7
    )::integer
      as total_weeks,

    b.break_days
      as instructional_break_days,

    (
      b.break_days / 7
    )::integer
      as instructional_break_weeks,

    (
      (
        e.ends_on
        - e.starts_on
        + 1
      ) / 7
      -
      b.break_days / 7
    )::integer
      as teaching_weeks,

    (
      (
        (
          e.ends_on
          - e.starts_on
          + 1
        ) / 7
        -
        b.break_days / 7
      ) = 4
    )
      as has_four_teaching_weeks

  from effective e
  cross join break_summary b;
$$;


revoke all
on function private.get_semester_week_summary(
  uuid,
  uuid
)
from public, anon, authenticated;


-- ============================================================
-- 10. CONTINUITY CHECK HELPERS
--
-- We create the validators now.
--
-- We intentionally DO NOT turn them into hard deferred
-- constraints yet until the client confirms the future-year
-- calendar rule.
-- ============================================================

create or replace function private.global_semester_calendar_is_contiguous()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with ordered as (
    select
      s.starts_on,
      s.ends_on,

      lag(s.ends_on)
      over (
        order by
          s.starts_on,
          s.id
      ) as previous_end

    from public.semesters s
  )

  select not exists (
    select 1
    from ordered o
    where o.previous_end is not null
      and o.starts_on <>
          o.previous_end + 1
  );
$$;


create or replace function private.branch_semester_calendar_is_contiguous(
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with effective as (
    select
      s.id,
      s.starts_on as default_starts_on,

      coalesce(
        o.starts_on,
        s.starts_on
      ) as effective_starts_on,

      coalesce(
        o.ends_on,
        s.ends_on
      ) as effective_ends_on

    from public.semesters s

    left join public.branch_semester_overrides o
      on o.semester_id = s.id
      and o.branch_id = p_branch_id
  ),

  ordered as (
    select
      e.effective_starts_on,
      e.effective_ends_on,

      lag(e.effective_ends_on)
      over (
        order by
          e.default_starts_on,
          e.id
      ) as previous_end

    from effective e
  )

  select not exists (
    select 1
    from ordered o
    where o.previous_end is not null
      and o.effective_starts_on <>
          o.previous_end + 1
  );
$$;


revoke all
on function private.global_semester_calendar_is_contiguous()
from public, anon, authenticated;


revoke all
on function private.branch_semester_calendar_is_contiguous(uuid)
from public, anon, authenticated;


-- ============================================================
-- 11. RLS / PRIVILEGES
--
-- semesters:
--   remain global defaults readable by active users
--
-- overrides / closures:
--   master = all
--   non-master = own branch
--
-- Direct writes remain denied.
-- ============================================================

revoke all
on table public.branch_semester_overrides
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table public.branch_semester_overrides
from authenticated;


grant select
on table public.branch_semester_overrides
to authenticated;


drop policy if exists
  branch_semester_overrides_select
on public.branch_semester_overrides;


create policy branch_semester_overrides_select
on public.branch_semester_overrides
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or branch_id = (
      select private.current_branch_id()
    )
  )
);


drop policy if exists
  closure_periods_select
on public.closure_periods;


create policy closure_periods_select
on public.closure_periods
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or branch_id = (
      select private.current_branch_id()
    )
  )
);


comment on table public.branch_semester_overrides is
  'Stores only branch semester date exceptions. Missing row means the branch follows the global semester default.';


comment on column public.closure_periods.closure_kind is
  'ordinary closures do not reduce the four-week instructional count; instructional_break closures do.';