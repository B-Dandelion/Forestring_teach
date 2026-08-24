-- ============================================================
-- Forestring v3
-- Global/default closure inheritance while preserving the
-- existing branch-materialized closure engine.
-- ============================================================

create table public.default_closure_periods (
  id uuid primary key default gen_random_uuid(),
  semester_id uuid references public.semesters(id) on delete restrict,
  starts_on date not null,
  ends_on date not null,
  reason text,
  closure_kind public.closure_kind not null default 'ordinary',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint default_closure_periods_date_check check (starts_on <= ends_on),
  constraint default_closure_periods_instructional_break_check check (
    closure_kind <> 'instructional_break'::public.closure_kind
    or (
      semester_id is not null
      and (ends_on - starts_on + 1) >= 7
      and mod(ends_on - starts_on + 1, 7) = 0
    )
  )
);

comment on table public.default_closure_periods is
  'Academy-wide default closure periods. Every branch inherits these through linked closure_periods rows unless that branch row is explicitly overridden.';

create index default_closure_periods_semester_date_idx
on public.default_closure_periods (semester_id, starts_on);

alter table public.default_closure_periods
add constraint default_closure_periods_no_overlap
exclude using gist (daterange(starts_on, ends_on + 1, '[)') with &&);

create trigger default_closure_periods_set_updated_at
before update on public.default_closure_periods
for each row execute function public.set_updated_at();

alter table public.default_closure_periods enable row level security;
revoke all on table public.default_closure_periods from anon;
revoke insert, update, delete, truncate, references, trigger
on table public.default_closure_periods from authenticated;
grant select on table public.default_closure_periods to authenticated;

create policy default_closure_periods_select
on public.default_closure_periods
for select to authenticated
using ((select private.is_active_user()));

create or replace function public.assert_default_closure_within_semester()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_starts_on date;
  v_ends_on date;
begin
  if new.semester_id is null then
    if new.closure_kind = 'instructional_break'::public.closure_kind then
      raise exception using errcode='P0001', message='FORESTRING_INSTRUCTIONAL_BREAK_REQUIRES_SEMESTER';
    end if;
    return new;
  end if;

  select s.starts_on, s.ends_on into v_starts_on, v_ends_on
  from public.semesters s where s.id = new.semester_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if new.starts_on < v_starts_on or new.ends_on > v_ends_on then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_OUTSIDE_SEMESTER';
  end if;

  return new;
end;
$$;

create trigger default_closure_periods_assert_semester_range
before insert or update of semester_id, starts_on, ends_on, closure_kind
on public.default_closure_periods
for each row execute function public.assert_default_closure_within_semester();

alter table public.closure_periods
add column default_closure_id uuid
references public.default_closure_periods(id) on delete restrict;

alter table public.closure_periods
add column is_overridden boolean not null default false;

create unique index closure_periods_branch_default_unique
on public.closure_periods (branch_id, default_closure_id)
where default_closure_id is not null;

create index closure_periods_default_idx
on public.closure_periods (default_closure_id, branch_id)
where default_closure_id is not null;

comment on column public.closure_periods.default_closure_id is
  'Inherited academy-wide default closure. NULL means branch-only closure.';
comment on column public.closure_periods.is_overridden is
  'True when this linked branch row intentionally differs from its default closure.';

create or replace function public.sync_closure_override_flag()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_default public.default_closure_periods%rowtype;
begin
  if new.default_closure_id is null then
    new.is_overridden := false;
    return new;
  end if;

  select * into v_default
  from public.default_closure_periods d
  where d.id = new.default_closure_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_NOT_FOUND';
  end if;

  new.is_overridden :=
       new.semester_id is distinct from v_default.semester_id
    or new.starts_on is distinct from v_default.starts_on
    or new.ends_on is distinct from v_default.ends_on
    or new.closure_kind is distinct from v_default.closure_kind
    or new.reason is distinct from v_default.reason;
  return new;
end;
$$;

create trigger closure_periods_sync_override_flag
before insert or update of default_closure_id, semester_id, starts_on, ends_on, closure_kind, reason
on public.closure_periods
for each row execute function public.sync_closure_override_flag();

create or replace function public.prevent_linked_closure_direct_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.default_closure_id is not null then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_BRANCH_DELETE_FORBIDDEN';
  end if;
  return old;
end;
$$;

create trigger closure_periods_prevent_linked_delete
before delete on public.closure_periods
for each row execute function public.prevent_linked_closure_direct_delete();

-- Promote only legacy closure groups that exist identically in every branch.
insert into public.default_closure_periods (
  semester_id, starts_on, ends_on, reason, closure_kind,
  created_by, created_at, updated_at
)
select
  cp.semester_id,
  cp.starts_on,
  cp.ends_on,
  cp.reason,
  cp.closure_kind,
  min(cp.created_by::text)::uuid,
  min(cp.created_at),
  max(cp.updated_at)
from public.closure_periods cp
group by cp.semester_id, cp.starts_on, cp.ends_on, cp.reason, cp.closure_kind
having count(distinct cp.branch_id) = (select count(*) from public.branches);

update public.closure_periods cp
set default_closure_id = d.id
from public.default_closure_periods d
where cp.default_closure_id is null
  and cp.semester_id is not distinct from d.semester_id
  and cp.starts_on = d.starts_on
  and cp.ends_on = d.ends_on
  and cp.closure_kind = d.closure_kind
  and cp.reason is not distinct from d.reason;

create or replace function public.seed_default_closures_for_new_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.closure_periods (
    semester_id, starts_on, ends_on, reason, created_by,
    branch_id, closure_kind, default_closure_id
  )
  select
    d.semester_id, d.starts_on, d.ends_on, d.reason, d.created_by,
    new.id, d.closure_kind, d.id
  from public.default_closure_periods d;
  return new;
end;
$$;

create trigger branches_seed_default_closures
after insert on public.branches
for each row execute function public.seed_default_closures_for_new_branch();

create or replace function public.upsert_default_closure_period(
  p_default_closure_id uuid,
  p_semester_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_closure_kind public.closure_kind,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_default_id uuid;
  v_existing public.default_closure_periods%rowtype;
  v_reason text;
  v_structural_changed boolean := true;
  v_changed boolean := true;
  v_branch record;
  v_bounds record;
  v_row public.closure_periods%rowtype;
begin
  select a.actor_id, a.actor_role into v_actor_id, v_actor_role
  from private.require_calendar_actor(null, true) a;

  if p_starts_on is null or p_ends_on is null or p_starts_on > p_ends_on then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_CLOSURE_RANGE';
  end if;
  if p_closure_kind is null then
    raise exception using errcode='P0001', message='FORESTRING_CLOSURE_KIND_REQUIRED';
  end if;
  if p_closure_kind = 'instructional_break'::public.closure_kind then
    if p_semester_id is null then
      raise exception using errcode='P0001', message='FORESTRING_INSTRUCTIONAL_BREAK_REQUIRES_SEMESTER';
    end if;
    if (p_ends_on - p_starts_on + 1) < 7
       or mod(p_ends_on - p_starts_on + 1, 7) <> 0 then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_INSTRUCTIONAL_BREAK_WEEK_STRUCTURE';
    end if;
  end if;
  if p_semester_id is not null and not exists (
    select 1 from public.semesters s where s.id = p_semester_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  if p_default_closure_id is not null then
    select * into v_existing
    from public.default_closure_periods d
    where d.id = p_default_closure_id for update;
    if not found then
      raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_NOT_FOUND';
    end if;
    v_default_id := v_existing.id;
    v_structural_changed :=
         v_existing.semester_id is distinct from p_semester_id
      or v_existing.starts_on is distinct from p_starts_on
      or v_existing.ends_on is distinct from p_ends_on
      or v_existing.closure_kind is distinct from p_closure_kind;
    v_changed := v_structural_changed or v_existing.reason is distinct from v_reason;
  else
    v_default_id := gen_random_uuid();
  end if;

  if p_semester_id is not null then
    for v_branch in select b.id from public.branches b loop
      select * into v_bounds
      from private.get_effective_semester_bounds(v_branch.id, p_semester_id);
      if not found or p_starts_on < v_bounds.starts_on or p_ends_on > v_bounds.ends_on then
        raise exception using
          errcode='P0001',
          message='FORESTRING_DEFAULT_CLOSURE_OUTSIDE_BRANCH_SEMESTER',
          detail='branch_id=' || v_branch.id::text;
      end if;
    end loop;
  end if;

  if v_structural_changed then
    for v_row in
      select cp.* from public.closure_periods cp
      where cp.default_closure_id = v_default_id and cp.is_overridden = false
      for update
    loop
      if v_row.closure_kind = 'instructional_break'::public.closure_kind
         and v_row.semester_id is not null
         and private.calendar_semester_is_materialized(v_row.semester_id, v_row.branch_id) then
        raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_DEFAULT_CLOSURE_IMMUTABLE';
      end if;
    end loop;

    if p_closure_kind = 'instructional_break'::public.closure_kind
       and p_semester_id is not null then
      for v_branch in select b.id from public.branches b loop
        if private.calendar_semester_is_materialized(p_semester_id, v_branch.id)
           and not exists (
             select 1 from public.closure_periods cp
             where cp.branch_id = v_branch.id
               and cp.default_closure_id = v_default_id
               and cp.is_overridden = true
           ) then
          raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_DEFAULT_CLOSURE_IMMUTABLE';
        end if;
      end loop;
    end if;
  end if;

  if not v_changed then
    return jsonb_build_object('defaultClosureId', v_default_id, 'changed', false);
  end if;

  begin
    if p_default_closure_id is null then
      insert into public.default_closure_periods (
        id, semester_id, starts_on, ends_on, reason, closure_kind, created_by
      ) values (
        v_default_id, p_semester_id, p_starts_on, p_ends_on,
        v_reason, p_closure_kind, v_actor_id
      );
    else
      update public.default_closure_periods
      set semester_id=p_semester_id, starts_on=p_starts_on, ends_on=p_ends_on,
          reason=v_reason, closure_kind=p_closure_kind
      where id=v_default_id;
    end if;
  exception when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_OVERLAP';
  end;

  begin
    update public.closure_periods cp
    set semester_id=p_semester_id, starts_on=p_starts_on, ends_on=p_ends_on,
        reason=v_reason, closure_kind=p_closure_kind
    where cp.default_closure_id=v_default_id and cp.is_overridden=false;

    insert into public.closure_periods (
      semester_id, starts_on, ends_on, reason, created_by,
      branch_id, closure_kind, default_closure_id
    )
    select p_semester_id, p_starts_on, p_ends_on, v_reason, v_actor_id,
           b.id, p_closure_kind, v_default_id
    from public.branches b
    where not exists (
      select 1 from public.closure_periods cp
      where cp.branch_id=b.id and cp.default_closure_id=v_default_id
    );
  exception when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_BRANCH_OVERLAP';
  end;

  insert into public.audit_events (event_type, effective_on, actor_id, details)
  values (
    case when p_default_closure_id is null then 'DEFAULT_CLOSURE_CREATED' else 'DEFAULT_CLOSURE_UPDATED' end,
    p_starts_on,
    v_actor_id,
    jsonb_build_object(
      'defaultClosureId', v_default_id,
      'semesterId', p_semester_id,
      'startsOn', p_starts_on,
      'endsOn', p_ends_on,
      'closureKind', p_closure_kind,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'defaultClosureId', v_default_id,
    'changed', true,
    'semesterId', p_semester_id,
    'startsOn', p_starts_on,
    'endsOn', p_ends_on,
    'closureKind', p_closure_kind,
    'reason', v_reason
  );
end;
$$;

create or replace function public.delete_default_closure_period(p_default_closure_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_existing public.default_closure_periods%rowtype;
  v_row public.closure_periods%rowtype;
begin
  select a.actor_id, a.actor_role into v_actor_id, v_actor_role
  from private.require_calendar_actor(null, true) a;

  select * into v_existing
  from public.default_closure_periods d
  where d.id=p_default_closure_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_NOT_FOUND';
  end if;

  for v_row in
    select cp.* from public.closure_periods cp
    where cp.default_closure_id=v_existing.id and cp.is_overridden=false
    for update
  loop
    if v_row.closure_kind='instructional_break'::public.closure_kind
       and v_row.semester_id is not null
       and private.calendar_semester_is_materialized(v_row.semester_id, v_row.branch_id) then
      raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_DEFAULT_CLOSURE_IMMUTABLE';
    end if;
  end loop;

  update public.closure_periods
  set default_closure_id=null
  where default_closure_id=v_existing.id and is_overridden=true;

  update public.closure_periods
  set default_closure_id=null
  where default_closure_id=v_existing.id and is_overridden=false;

  delete from public.closure_periods cp
  where cp.default_closure_id is null
    and cp.semester_id is not distinct from v_existing.semester_id
    and cp.starts_on=v_existing.starts_on
    and cp.ends_on=v_existing.ends_on
    and cp.closure_kind=v_existing.closure_kind
    and cp.reason is not distinct from v_existing.reason
    and cp.is_overridden=false;

  delete from public.default_closure_periods where id=v_existing.id;

  insert into public.audit_events (event_type, effective_on, actor_id, details)
  values (
    'DEFAULT_CLOSURE_DELETED',
    v_existing.starts_on,
    v_actor_id,
    jsonb_build_object(
      'defaultClosureId', v_existing.id,
      'semesterId', v_existing.semester_id,
      'startsOn', v_existing.starts_on,
      'endsOn', v_existing.ends_on,
      'closureKind', v_existing.closure_kind,
      'reason', v_existing.reason
    )
  );

  return jsonb_build_object('defaultClosureId', v_existing.id, 'deleted', true);
end;
$$;

create or replace function public.reset_branch_closure_override(p_closure_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_existing public.closure_periods%rowtype;
  v_default public.default_closure_periods%rowtype;
begin
  select * into v_existing from public.closure_periods cp
  where cp.id=p_closure_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_CLOSURE_NOT_FOUND';
  end if;

  select a.actor_id, a.actor_role into v_actor_id, v_actor_role
  from private.require_calendar_actor(v_existing.branch_id, false) a;

  if v_existing.default_closure_id is null then
    raise exception using errcode='P0001', message='FORESTRING_CLOSURE_HAS_NO_DEFAULT';
  end if;

  select * into v_default from public.default_closure_periods d
  where d.id=v_existing.default_closure_id;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_NOT_FOUND';
  end if;

  if not v_existing.is_overridden then
    return jsonb_build_object('closureId', v_existing.id, 'changed', false);
  end if;

  if v_existing.closure_kind='instructional_break'::public.closure_kind
     and v_existing.semester_id is not null
     and private.calendar_semester_is_materialized(v_existing.semester_id, v_existing.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  if v_default.closure_kind='instructional_break'::public.closure_kind
     and v_default.semester_id is not null
     and private.calendar_semester_is_materialized(v_default.semester_id, v_existing.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  begin
    update public.closure_periods
    set semester_id=v_default.semester_id,
        starts_on=v_default.starts_on,
        ends_on=v_default.ends_on,
        reason=v_default.reason,
        closure_kind=v_default.closure_kind
    where id=v_existing.id;
  exception when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_CLOSURE_OVERLAP';
  end;

  insert into public.audit_events (branch_id, event_type, effective_on, actor_id, details)
  values (
    v_existing.branch_id,
    'BRANCH_CLOSURE_OVERRIDE_RESET',
    v_default.starts_on,
    v_actor_id,
    jsonb_build_object('closureId', v_existing.id, 'defaultClosureId', v_default.id)
  );

  return jsonb_build_object(
    'closureId', v_existing.id,
    'defaultClosureId', v_default.id,
    'changed', true
  );
end;
$$;

create or replace function public.delete_closure_period(p_closure_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_existing public.closure_periods%rowtype;
begin
  select * into v_existing from public.closure_periods cp
  where cp.id=p_closure_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_CLOSURE_NOT_FOUND';
  end if;

  select a.actor_id, a.actor_role into v_actor_id, v_actor_role
  from private.require_calendar_actor(v_existing.branch_id, false) a;

  if v_existing.default_closure_id is not null then
    raise exception using errcode='P0001', message='FORESTRING_DEFAULT_CLOSURE_BRANCH_DELETE_FORBIDDEN';
  end if;

  if v_existing.closure_kind='instructional_break'::public.closure_kind
     and v_existing.semester_id is not null
     and private.calendar_semester_is_materialized(v_existing.semester_id, v_existing.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE';
  end if;

  delete from public.closure_periods where id=v_existing.id;

  insert into public.audit_events (
    branch_id, semester_id, event_type, effective_on, actor_id, details
  ) values (
    v_existing.branch_id,
    null,
    'CLOSURE_DELETED',
    v_existing.starts_on,
    v_actor_id,
    jsonb_build_object(
      'closureId', v_existing.id,
      'semesterId', v_existing.semester_id,
      'startsOn', v_existing.starts_on,
      'endsOn', v_existing.ends_on,
      'closureKind', v_existing.closure_kind,
      'reason', v_existing.reason
    )
  );

  return jsonb_build_object('closureId', v_existing.id, 'deleted', true);
end;
$$;

revoke all on function public.upsert_default_closure_period(uuid, uuid, date, date, public.closure_kind, text)
from public, anon;
grant execute on function public.upsert_default_closure_period(uuid, uuid, date, date, public.closure_kind, text)
to authenticated;

revoke all on function public.delete_default_closure_period(uuid) from public, anon;
grant execute on function public.delete_default_closure_period(uuid) to authenticated;

revoke all on function public.reset_branch_closure_override(uuid) from public, anon;
grant execute on function public.reset_branch_closure_override(uuid) to authenticated;
