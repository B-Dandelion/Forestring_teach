-- ============================================================
-- Forestring v3
-- General immutable audit event ledger
--
-- This table records WHO changed WHAT and WHEN.
--
-- It is NOT a source for business calculations.
-- Business state remains in profiles / plans / assignments /
-- series / lessons / rights.
-- ============================================================


-- ============================================================
-- AUDIT EVENTS
--
-- event_type intentionally uses text instead of enum.
--
-- Reason:
-- audit event categories will naturally expand as admin
-- functionality grows, and old audit rows must remain readable
-- without enum migration coupling.
-- ============================================================

create table public.audit_events (
  id uuid primary key
    default gen_random_uuid(),

  -- Main profile affected by the operation.
  --
  -- Examples:
  -- student whose teacher changed,
  -- user whose PIN was reset,
  -- teacher whose work hours changed.
  subject_profile_id uuid
    references public.profiles(id)
    on delete set null,

  -- Historical branch context of the event.
  branch_id uuid
    references public.branches(id)
    on delete restrict,

  semester_id uuid
    references public.semesters(id)
    on delete restrict,

  event_type text not null,

  -- Business-effective date.
  --
  -- created_at:
  --   when the operation was recorded
  --
  -- effective_on:
  --   when the change takes effect
  --
  -- Example:
  -- teacher change entered 8/20,
  -- effective from 9/1.
  effective_on date,

  actor_id uuid
    references public.profiles(id)
    on delete set null,

  -- Human / structured metadata.
  --
  -- Examples:
  -- before/after values,
  -- warning overrides,
  -- related entity IDs.
  --
  -- NEVER store:
  -- PIN
  -- password
  -- pepper
  -- credential hash
  details jsonb not null
    default '{}'::jsonb,

  created_at timestamptz not null
    default now(),

  constraint audit_events_type_not_blank
    check (
      length(btrim(event_type)) > 0
    ),

  constraint audit_events_details_object_check
    check (
      jsonb_typeof(details) = 'object'
    )
);


create index audit_events_subject_created_idx
on public.audit_events (
  subject_profile_id,
  created_at desc
)
where subject_profile_id is not null;


create index audit_events_branch_created_idx
on public.audit_events (
  branch_id,
  created_at desc
)
where branch_id is not null;


create index audit_events_semester_created_idx
on public.audit_events (
  semester_id,
  created_at desc
)
where semester_id is not null;


create index audit_events_type_created_idx
on public.audit_events (
  event_type,
  created_at desc
);


alter table public.audit_events
enable row level security;


-- ============================================================
-- IMMUTABILITY
--
-- An audit entry may never be edited or deleted.
-- Corrections are represented by another event.
-- ============================================================

create or replace function public.prevent_audit_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'FORESTRING_AUDIT_EVENT_IMMUTABLE';
end;
$$;


create trigger audit_events_immutable
before update or delete
on public.audit_events
for each row
execute function public.prevent_audit_event_mutation();


-- ============================================================
-- PRIVILEGES
--
-- Flutter never inserts audit events directly.
-- Trusted RPC / Edge Functions create them as part of the same
-- transaction as the business mutation.
-- ============================================================

revoke all
on table public.audit_events
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table public.audit_events
from authenticated;


grant select
on table public.audit_events
to authenticated;


-- ============================================================
-- RLS
--
-- master:
--   all
--
-- manager:
--   own branch
--
-- teacher/student:
--   own subject history only
--
-- This can be tightened later for event types containing
-- sensitive administrative details.
-- ============================================================

create policy audit_events_select
on public.audit_events
for select
to authenticated
using (
  (select private.is_active_user())

  and (
    (select private.is_master())

    or private.manager_has_branch(
      branch_id
    )

    or subject_profile_id =
      (select auth.uid())
  )
);


comment on table public.audit_events is
  'Immutable human/audit history. Never use this table as the authoritative source for scheduling or entitlement calculations.';


comment on column public.audit_events.effective_on is
  'Business-effective date, which may differ from the timestamp when the audit event was created.';


comment on column public.audit_events.details is
  'Structured audit metadata. Authentication secrets or PIN values must never be stored here.';