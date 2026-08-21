-- ============================================================
-- Forestring v3
-- Authoritative student enrollment / branch membership history
--
-- students + profiles:
--   current operational state
--
-- student_enrollment_periods:
--   historical enrollment/branch periods
--
-- audit_events:
--   human audit only, never calculation source
-- ============================================================


create table public.student_enrollment_periods (
  id uuid primary key
    default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  starts_on date not null,

  -- Inclusive.
  --
  -- withdrawal_date = 2026-09-15
  -- -> enrollment ends_on = 2026-09-14
  ends_on date,

  started_by uuid
    references public.profiles(id)
    on delete set null,

  ended_by uuid
    references public.profiles(id)
    on delete set null,

  start_reason text not null
    default 'initial',

  end_reason text,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint student_enrollment_periods_dates_check
    check (
      ends_on is null
      or ends_on >= starts_on
    ),

  constraint student_enrollment_periods_start_reason_check
    check (
      length(btrim(start_reason)) > 0
    ),

  constraint student_enrollment_periods_end_reason_check
    check (
      end_reason is null
      or length(btrim(end_reason)) > 0
    )
);


create index student_enrollment_periods_student_idx
on public.student_enrollment_periods (
  student_id,
  starts_on
);


create index student_enrollment_periods_branch_idx
on public.student_enrollment_periods (
  branch_id,
  starts_on
);


-- A student cannot belong to two enrollment periods at once.
alter table public.student_enrollment_periods
add constraint student_enrollment_periods_no_overlap
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


create trigger student_enrollment_periods_set_updated_at
before update
on public.student_enrollment_periods
for each row
execute function public.set_updated_at();


alter table public.student_enrollment_periods
enable row level security;



-- ============================================================
-- BACKFILL CURRENT HOSTED STUDENTS
--
-- Existing historical start dates are approximate because the
-- old schema did not store enrollment periods explicitly.
--
-- Real legacy-data migration can refine these rows later.
-- ============================================================

insert into public.student_enrollment_periods (
  student_id,
  branch_id,
  starts_on,
  ends_on,
  started_by,
  ended_by,
  start_reason,
  end_reason
)
select
  s.id,

  p.branch_id,

  case
    when s.withdrawal_date is not null then
      least(
        (
          p.created_at
          at time zone 'Asia/Seoul'
        )::date,

        s.withdrawal_date - 1
      )

    else
      (
        p.created_at
        at time zone 'Asia/Seoul'
      )::date
  end,

  case
    when s.withdrawal_date is not null then
      s.withdrawal_date - 1

    else
      null
  end,

  null,
  null,

  'legacy_backfill',

  case
    when s.status =
         'withdrawn'::public.student_status
      then 'withdrawal'

    when s.withdrawal_date is not null
      then 'withdrawal_scheduled'

    else null
  end

from public.students s

join public.profiles p
  on p.id = s.id

where p.branch_id is not null

  and not exists (
    select 1

    from public.student_enrollment_periods ep

    where ep.student_id =
          s.id
  );



-- ============================================================
-- AUTOMATIC ENROLLMENT LIFECYCLE SYNC
--
-- This means individual RPCs do not each need to remember to
-- maintain enrollment history.
-- ============================================================

create or replace function public.sync_student_enrollment_period()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_branch_id uuid;

  v_period_id uuid;

  v_today date;
begin

  v_actor_id :=
    auth.uid();


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  select p.branch_id
  into v_branch_id

  from public.profiles p

  where p.id =
        new.id;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- INITIAL STUDENT CREATION
  -- ==========================================================

  if tg_op = 'INSERT' then

    insert into public.student_enrollment_periods (
      student_id,
      branch_id,
      starts_on,
      started_by,
      start_reason
    )
    values (
      new.id,
      v_branch_id,
      v_today,
      v_actor_id,
      'initial'
    );

    return new;

  end if;


  -- ==========================================================
  -- WITHDRAWAL SCHEDULED / DATE CHANGED
  -- ==========================================================

  if old.status =
       'active'::public.student_status

     and new.status =
       'active'::public.student_status

     and new.withdrawal_date is not null

     and old.withdrawal_date
         is distinct from
         new.withdrawal_date then

    select ep.id
    into v_period_id

    from public.student_enrollment_periods ep

    where ep.student_id =
          new.id

    order by
      ep.starts_on desc,
      ep.created_at desc

    limit 1

    for update;


    if v_period_id is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
    end if;


    update public.student_enrollment_periods
    set
      ends_on =
        new.withdrawal_date - 1,

      ended_by =
        v_actor_id,

      end_reason =
        'withdrawal_scheduled'

    where id =
          v_period_id;


    return new;

  end if;


  -- ==========================================================
  -- SCHEDULED WITHDRAWAL CANCELED
  -- ==========================================================

  if old.status =
       'active'::public.student_status

     and new.status =
       'active'::public.student_status

     and old.withdrawal_date is not null

     and new.withdrawal_date is null then

    select ep.id
    into v_period_id

    from public.student_enrollment_periods ep

    where ep.student_id =
          new.id

    order by
      ep.starts_on desc,
      ep.created_at desc

    limit 1

    for update;


    if v_period_id is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
    end if;


    update public.student_enrollment_periods
    set
      ends_on =
        null,

      ended_by =
        null,

      end_reason =
        null

    where id =
          v_period_id;


    return new;

  end if;


  -- ==========================================================
  -- WITHDRAWAL FINALIZED
  -- ==========================================================

  if old.status =
       'active'::public.student_status

     and new.status =
       'withdrawn'::public.student_status then

    if new.withdrawal_date is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_WITHDRAWAL_DATE_REQUIRED';
    end if;


    select ep.id
    into v_period_id

    from public.student_enrollment_periods ep

    where ep.student_id =
          new.id

    order by
      ep.starts_on desc,
      ep.created_at desc

    limit 1

    for update;


    if v_period_id is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
    end if;


    update public.student_enrollment_periods
    set
      ends_on =
        new.withdrawal_date - 1,

      ended_by =
        v_actor_id,

      end_reason =
        'withdrawal'

    where id =
          v_period_id;


    return new;

  end if;


  -- ==========================================================
  -- REACTIVATION
  -- ==========================================================

  if old.status =
       'withdrawn'::public.student_status

     and new.status =
       'active'::public.student_status then

    if new.withdrawal_date is not null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REACTIVATION_WITHDRAWAL_DATE_INVALID';
    end if;


    insert into public.student_enrollment_periods (
      student_id,
      branch_id,
      starts_on,
      started_by,
      start_reason
    )
    values (
      new.id,
      v_branch_id,
      v_today,
      v_actor_id,
      'reactivation'
    );


    return new;

  end if;


  return new;

end;
$$;


create trigger students_sync_enrollment_period
after insert
or update of
  status,
  withdrawal_date
on public.students
for each row
execute function public.sync_student_enrollment_period();



-- ============================================================
-- DATE-AWARE BRANCH HELPER
--
-- This becomes useful for future branch transfer and other
-- effective-date business rules.
-- ============================================================

create or replace function private.student_branch_on_date(
  p_student_id uuid,
  p_date date
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select ep.branch_id

  from public.student_enrollment_periods ep

  where ep.student_id =
        p_student_id

    and ep.starts_on <=
        p_date

    and (
      ep.ends_on is null
      or ep.ends_on >=
         p_date
    )

  order by ep.starts_on desc

  limit 1;
$$;


revoke all
on function private.student_branch_on_date(
  uuid,
  date
)
from public, anon, authenticated;



-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on table public.student_enrollment_periods
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table public.student_enrollment_periods
from authenticated;


grant select
on table public.student_enrollment_periods
to authenticated;



-- ============================================================
-- RLS
-- ============================================================

create policy student_enrollment_periods_select
on public.student_enrollment_periods
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
  )
);


comment on table public.student_enrollment_periods is
  'Authoritative enrollment and historical branch membership periods. Current state remains in students/profiles; audit_events is not used for business calculations.';