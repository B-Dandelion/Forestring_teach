do $block$
declare
  v_row record;
  v_existing_start date;
  v_existing_end date;
begin
  for v_row in
    select *
    from (
      values
        ('2027-01', date '2026-12-28', date '2027-01-24'),
        ('2027-02', date '2027-01-25', date '2027-02-28'),
        ('2027-03', date '2027-03-01', date '2027-03-28'),
        ('2027-04', date '2027-03-29', date '2027-04-25'),
        ('2027-05', date '2027-04-26', date '2027-05-30'),
        ('2027-06', date '2027-05-31', date '2027-06-27'),
        ('2027-07', date '2027-06-28', date '2027-07-25'),
        ('2027-08', date '2027-07-26', date '2027-08-29'),
        ('2027-09', date '2027-08-30', date '2027-10-03'),
        ('2027-10', date '2027-10-04', date '2027-10-31'),
        ('2027-11', date '2027-11-01', date '2027-11-28'),
        ('2027-12', date '2027-11-29', date '2027-12-26')
    ) as x(code, starts_on, ends_on)
  loop
    select s.starts_on, s.ends_on
    into v_existing_start, v_existing_end
    from public.semesters s
    where s.code = v_row.code;

    if found
       and (
         v_existing_start <> v_row.starts_on
         or v_existing_end <> v_row.ends_on
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_PROVISIONAL_2027_SEMESTER_CONFLICT_' || v_row.code;
    end if;
  end loop;
end;
$block$;

insert into public.semesters (code, starts_on, ends_on)
values
  ('2027-01', date '2026-12-28', date '2027-01-24'),
  ('2027-02', date '2027-01-25', date '2027-02-28'),
  ('2027-03', date '2027-03-01', date '2027-03-28'),
  ('2027-04', date '2027-03-29', date '2027-04-25'),
  ('2027-05', date '2027-04-26', date '2027-05-30'),
  ('2027-06', date '2027-05-31', date '2027-06-27'),
  ('2027-07', date '2027-06-28', date '2027-07-25'),
  ('2027-08', date '2027-07-26', date '2027-08-29'),
  ('2027-09', date '2027-08-30', date '2027-10-03'),
  ('2027-10', date '2027-10-04', date '2027-10-31'),
  ('2027-11', date '2027-11-01', date '2027-11-28'),
  ('2027-12', date '2027-11-29', date '2027-12-26')
on conflict (code) do nothing;

with provisional_breaks as (
  select s.id as semester_id,
         date '2027-02-05' as starts_on,
         date '2027-02-11' as ends_on,
         '[임시] 2027년 2월 설 휴원'::text as reason
  from public.semesters s
  where s.code = '2027-02'

  union all

  select s.id,
         date '2027-05-01',
         date '2027-05-07',
         '[임시] 2027년 5월 휴원'
  from public.semesters s
  where s.code = '2027-05'

  union all

  select s.id,
         date '2027-07-26',
         date '2027-08-01',
         '[임시] 2027년 여름 휴원'
  from public.semesters s
  where s.code = '2027-08'

  union all

  select s.id,
         date '2027-09-13',
         date '2027-09-19',
         '[임시] 2027년 추석 휴원'
  from public.semesters s
  where s.code = '2027-09'
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
  pb.semester_id,
  b.id,
  pb.starts_on,
  pb.ends_on,
  pb.reason,
  'instructional_break'::public.closure_kind
from provisional_breaks pb
cross join public.branches b
where not exists (
  select 1
  from public.branch_semester_overrides o
  where o.branch_id = b.id
    and o.semester_id = pb.semester_id
)
and not exists (
  select 1
  from public.closure_periods cp
  where cp.branch_id = b.id
    and cp.semester_id = pb.semester_id
    and cp.starts_on = pb.starts_on
    and cp.ends_on = pb.ends_on
    and cp.closure_kind = 'instructional_break'::public.closure_kind
);

do $validation$
begin
  if (
    select count(*)
    from public.semesters s
    where s.code like '2027-%'
  ) <> 12 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROVISIONAL_2027_SEMESTER_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from (
      select
        s.code,
        s.starts_on,
        lag(s.ends_on) over (order by s.starts_on) as previous_end
      from public.semesters s
      where s.code = '2026-12'
         or s.code like '2027-%'
    ) ordered
    where ordered.code like '2027-%'
      and ordered.starts_on <> ordered.previous_end + 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROVISIONAL_2027_SEMESTER_GAP';
  end if;

  if exists (
    with teaching_day_counts as (
      select
        b.id as branch_id,
        s.code,
        extract(isodow from d.day)::integer as weekday,
        count(*)::integer as teaching_day_count
      from public.branches b
      cross join public.semesters s
      cross join lateral generate_series(
        s.starts_on::timestamp,
        s.ends_on::timestamp,
        interval '1 day'
      ) as d(day)
      where s.code like '2027-%'
        and not exists (
          select 1
          from public.branch_semester_overrides o
          where o.branch_id = b.id
            and o.semester_id = s.id
        )
        and not exists (
          select 1
          from public.closure_periods cp
          where cp.branch_id = b.id
            and d.day::date between cp.starts_on and cp.ends_on
        )
      group by
        b.id,
        s.code,
        extract(isodow from d.day)
    )
    select 1
    from teaching_day_counts t
    where t.teaching_day_count <> 4
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROVISIONAL_2027_TEACHING_DAY_COUNT_MISMATCH';
  end if;
end;
$validation$;

