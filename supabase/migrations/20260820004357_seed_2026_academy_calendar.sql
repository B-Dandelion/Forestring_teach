-- ============================================================
-- Forestring v3
-- Official 2026 academy calendar
--
-- Source: Forestring Kids Violin 2026 calendar.
--
-- Global semester dates are inserted once.
-- Official instructional breaks are copied to branches that
-- follow the global semester dates.
--
-- Existing conflicting calendar data is NEVER overwritten.
-- ============================================================


do $$
declare
  v_row record;
  v_existing_start date;
  v_existing_end date;
begin

  -- ==========================================================
  -- 1. VERIFY EXISTING SEMESTERS
  -- ==========================================================

  for v_row in
    select *
    from (
      values
        ('2026-01', date '2025-12-29', date '2026-01-25'),
        ('2026-02', date '2026-01-26', date '2026-03-01'),
        ('2026-03', date '2026-03-02', date '2026-03-29'),
        ('2026-04', date '2026-03-30', date '2026-04-26'),
        ('2026-05', date '2026-04-27', date '2026-05-31'),
        ('2026-06', date '2026-06-01', date '2026-06-28'),
        ('2026-07', date '2026-06-29', date '2026-07-26'),
        ('2026-08', date '2026-07-27', date '2026-08-30'),
        ('2026-09', date '2026-08-31', date '2026-10-04'),
        ('2026-10', date '2026-10-05', date '2026-11-01'),
        ('2026-11', date '2026-11-02', date '2026-11-29'),
        ('2026-12', date '2026-11-30', date '2026-12-27')
    ) as x(
      code,
      starts_on,
      ends_on
    )
  loop

    select
      s.starts_on,
      s.ends_on
    into
      v_existing_start,
      v_existing_end
    from public.semesters s
    where s.code = v_row.code;


    if found
       and (
         v_existing_start <> v_row.starts_on
         or
         v_existing_end <> v_row.ends_on
       ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_2026_SEMESTER_CONFLICT_' ||
          v_row.code;

    end if;

  end loop;


  -- ==========================================================
  -- 2. INSERT MISSING SEMESTERS
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values
    ('2026-01', '2025-12-29', '2026-01-25'),
    ('2026-02', '2026-01-26', '2026-03-01'),
    ('2026-03', '2026-03-02', '2026-03-29'),
    ('2026-04', '2026-03-30', '2026-04-26'),
    ('2026-05', '2026-04-27', '2026-05-31'),
    ('2026-06', '2026-06-01', '2026-06-28'),
    ('2026-07', '2026-06-29', '2026-07-26'),
    ('2026-08', '2026-07-27', '2026-08-30'),
    ('2026-09', '2026-08-31', '2026-10-04'),
    ('2026-10', '2026-10-05', '2026-11-01'),
    ('2026-11', '2026-11-02', '2026-11-29'),
    ('2026-12', '2026-11-30', '2026-12-27')

  on conflict (code)
  do nothing;

end;
$$;


-- ============================================================
-- 3. OFFICIAL INSTRUCTIONAL BREAKS
--
-- A branch with an explicit semester-date override is skipped.
-- Its closure calendar must be configured explicitly.
-- ============================================================

with official_breaks as (

  select
    s.id as semester_id,
    date '2026-02-13' as starts_on,
    date '2026-02-19' as ends_on,
    '2026년 2월 휴원'::text as reason
  from public.semesters s
  where s.code = '2026-02'

  union all

  select
    s.id,
    date '2026-05-01',
    date '2026-05-07',
    '2026년 5월 휴원'
  from public.semesters s
  where s.code = '2026-05'

  union all

  select
    s.id,
    date '2026-07-27',
    date '2026-08-02',
    '2026년 8월 휴원'
  from public.semesters s
  where s.code = '2026-08'

  union all

  select
    s.id,
    date '2026-09-21',
    date '2026-09-27',
    '2026년 9월 휴원'
  from public.semesters s
  where s.code = '2026-09'
)

insert into public.closure_periods (
  semester_id,
  branch_id,
  starts_on,
  ends_on,
  reason,
  closure_kind
)
select
  ob.semester_id,
  b.id,
  ob.starts_on,
  ob.ends_on,
  ob.reason,
  'instructional_break'::public.closure_kind

from official_breaks ob

cross join public.branches b

where not exists (
  select 1
  from public.branch_semester_overrides o
  where o.branch_id = b.id
    and o.semester_id = ob.semester_id
)

and not exists (
  select 1
  from public.closure_periods cp
  where cp.branch_id = b.id
    and cp.semester_id = ob.semester_id
    and cp.starts_on = ob.starts_on
    and cp.ends_on = ob.ends_on
    and cp.closure_kind =
        'instructional_break'::public.closure_kind
);