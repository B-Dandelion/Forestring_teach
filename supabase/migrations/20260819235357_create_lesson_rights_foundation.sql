-- ============================================================
-- Forestring v3
-- Common lesson rights + cancellation ledger foundation
--
-- This is additive.
-- Existing lesson_rebooking_credits remain temporarily active
-- until cancellation/rebooking RPCs are migrated.
-- ============================================================


-- ============================================================
-- 1. ENUMS
-- ============================================================

create type public.lesson_right_origin as enum (
  'regular_base',
  'flex_base',
  'carryover'
);


create type public.lesson_right_status as enum (
  'available',
  'reserved',
  'consumed',
  'expired',
  'revoked'
);


create type public.lesson_cancellation_origin as enum (
  'student',
  'academy'
);


-- ============================================================
-- 2. LESSON RIGHTS
--
-- One row = entitlement to one lesson.
--
-- Important:
-- duration_minutes is the entitlement/default duration.
--
-- A privileged one-off lesson edit may change
-- lessons.duration_minutes WITHOUT changing this value.
-- ============================================================

create table public.lesson_rights (
  id uuid primary key
    default gen_random_uuid(),

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  -- Historical / operational branch ownership.
  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  -- Semester where the entitlement originated.
  source_semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  -- Semester where it may currently be used.
  usable_semester_id uuid not null
    references public.semesters(id)
    on delete restrict,

  -- Only regular_base rights belong to a logical regular slot.
  --
  -- Carryover becomes freely bookable and therefore does NOT
  -- stay tied to the old regular schedule slot.
  schedule_slot_id uuid,

  -- Carryover points to the original base right.
  source_right_id uuid
    references public.lesson_rights(id)
    on delete restrict,

  origin public.lesson_right_origin
    not null,

  -- Stable entitlement number.
  --
  -- regular:
  --   1..4 per schedule slot / semester
  --
  -- flex:
  --   1..N per student / semester
  --
  -- carryover:
  --   copied from the source right for traceability.
  sequence_no integer not null,

  -- Entitlement/default duration snapshot.
  --
  -- 15/30/60 = normal presets.
  -- Other 15-minute multiples are allowed for privileged
  -- administrative configuration.
  duration_minutes integer not null,

  status public.lesson_right_status
    not null
    default 'available',

  -- Base right = 0
  -- Carried right = 1
  --
  -- Recursive carryover is prohibited.
  carryover_count smallint
    not null
    default 0,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  issued_at timestamptz not null
    default now(),

  reserved_at timestamptz,

  consumed_at timestamptz,

  expired_at timestamptz,

  revoked_at timestamptz,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),


  constraint lesson_rights_sequence_check
    check (
      sequence_no > 0
    ),


  -- Technical duration rule only.
  constraint lesson_rights_duration_check
    check (
      duration_minutes > 0
      and duration_minutes <= 720
      and mod(
        duration_minutes,
        15
      ) = 0
    ),


  constraint lesson_rights_carryover_count_check
    check (
      carryover_count between 0 and 1
    ),


  -- Base entitlements are usable in their source semester.
  -- Carryover entitlements move to another semester.
  constraint lesson_rights_semester_usage_check
    check (
      (
        origin in (
          'regular_base'::public.lesson_right_origin,
          'flex_base'::public.lesson_right_origin
        )

        and usable_semester_id =
            source_semester_id
      )

      or

      (
        origin =
          'carryover'::public.lesson_right_origin

        and usable_semester_id <>
            source_semester_id
      )
    ),


  -- Structural meaning of each right type.
  constraint lesson_rights_origin_structure_check
    check (
      (
        origin =
          'regular_base'::public.lesson_right_origin

        and schedule_slot_id is not null

        and source_right_id is null

        and carryover_count = 0

        and sequence_no between 1 and 4
      )

      or

      (
        origin =
          'flex_base'::public.lesson_right_origin

        and schedule_slot_id is null

        and source_right_id is null

        and carryover_count = 0
      )

      or

      (
        origin =
          'carryover'::public.lesson_right_origin

        and schedule_slot_id is null

        and source_right_id is not null

        and carryover_count = 1
      )
    ),


  -- If a right belongs to a regular slot, student + branch must
  -- match that logical slot.
  constraint lesson_rights_schedule_slot_identity_fk
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
    on delete restrict
);


-- ============================================================
-- 3. RIGHT UNIQUENESS
-- ============================================================

-- Exactly one #1/#2/#3/#4 entitlement per regular slot.
create unique index lesson_rights_regular_sequence_unique
on public.lesson_rights (
  source_semester_id,
  schedule_slot_id,
  sequence_no
)
where origin =
  'regular_base'::public.lesson_right_origin;


-- Flex #1..N are unique per student / source semester.
create unique index lesson_rights_flex_sequence_unique
on public.lesson_rights (
  student_id,
  source_semester_id,
  sequence_no
)
where origin =
  'flex_base'::public.lesson_right_origin;


-- One original right can be carried at most once.
create unique index lesson_rights_source_carryover_unique
on public.lesson_rights (
  source_right_id
)
where origin =
  'carryover'::public.lesson_right_origin;


create index lesson_rights_student_usable_status_idx
on public.lesson_rights (
  student_id,
  usable_semester_id,
  status
);


create index lesson_rights_branch_semester_idx
on public.lesson_rights (
  branch_id,
  usable_semester_id,
  status
);


create index lesson_rights_schedule_slot_idx
on public.lesson_rights (
  schedule_slot_id,
  source_semester_id
)
where schedule_slot_id is not null;


create trigger lesson_rights_set_updated_at
before update
on public.lesson_rights
for each row
execute function public.set_updated_at();


alter table public.lesson_rights
enable row level security;


-- ============================================================
-- 4. CARRYOVER SOURCE INTEGRITY
--
-- Carryover:
--   - must come directly from a base right
--   - may never come from another carryover
--   - keeps the original entitlement duration
--   - keeps the original sequence number
--
-- Branch equality is intentionally NOT required because an
-- explicit future branch-transfer operation may carry a valid
-- entitlement into another branch.
-- ============================================================

create or replace function public.assert_lesson_right_carryover_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source_student_id uuid;
  v_source_origin public.lesson_right_origin;
  v_source_sequence_no integer;
  v_source_duration_minutes integer;
  v_source_semester_id uuid;
  v_source_carryover_count smallint;
begin

  if new.origin <>
     'carryover'::public.lesson_right_origin then
    return new;
  end if;


  select
    r.student_id,
    r.origin,
    r.sequence_no,
    r.duration_minutes,
    r.source_semester_id,
    r.carryover_count
  into
    v_source_student_id,
    v_source_origin,
    v_source_sequence_no,
    v_source_duration_minutes,
    v_source_semester_id,
    v_source_carryover_count
  from public.lesson_rights r
  where r.id = new.source_right_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_SOURCE_RIGHT_NOT_FOUND';
  end if;


  if v_source_origin =
     'carryover'::public.lesson_right_origin
     or v_source_carryover_count <> 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_RECURSIVE_CARRYOVER_FORBIDDEN';

  end if;


  if new.student_id <>
     v_source_student_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_STUDENT_MISMATCH';

  end if;


  if new.source_semester_id <>
     v_source_semester_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_SOURCE_SEMESTER_MISMATCH';

  end if;


  if new.duration_minutes <>
     v_source_duration_minutes then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_DURATION_MISMATCH';

  end if;


  if new.sequence_no <>
     v_source_sequence_no then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_SEQUENCE_MISMATCH';

  end if;


  return new;
end;
$$;


create trigger lesson_rights_assert_carryover_source
before insert
or update of
  student_id,
  source_semester_id,
  source_right_id,
  origin,
  sequence_no,
  duration_minutes,
  carryover_count
on public.lesson_rights
for each row
execute function public.assert_lesson_right_carryover_source();


-- ============================================================
-- 5. LINK CANONICAL LESSON TO ENTITLEMENT
--
-- Existing v3 lessons remain nullable temporarily.
--
-- Final production-generated regular/flex lessons will always
-- have one lesson_right_id.
--
-- One right always reuses one canonical lesson row when
-- canceled/rebooked.
-- ============================================================

alter table public.lessons
add column lesson_right_id uuid
references public.lesson_rights(id)
on delete restrict;


create unique index lessons_lesson_right_unique
on public.lessons (
  lesson_right_id
)
where lesson_right_id is not null;


create index lessons_student_right_idx
on public.lessons (
  student_id,
  lesson_right_id
)
where lesson_right_id is not null;


-- ============================================================
-- 6. FLEX LESSON TYPE
--
-- regular:
--   recurring series + occurrence identity
--
-- flex:
--   standalone actual lesson using a flex/carryover right
--
-- makeup:
--   standalone special lesson
-- ============================================================

alter table public.lessons
drop constraint if exists
  lessons_type_series_check;


alter table public.lessons
add constraint lessons_type_series_check
check (
  (
    lesson_type =
      'regular'::public.lesson_type

    and series_id is not null

    and occurrence_at is not null
  )

  or

  (
    lesson_type in (
      'flex'::public.lesson_type,
      'makeup'::public.lesson_type
    )

    and series_id is null

    and occurrence_at is null
  )
);


-- A normal flex booking always consumes/reserves an entitlement.
alter table public.lessons
add constraint lessons_flex_requires_right_check
check (
  lesson_type <>
    'flex'::public.lesson_type

  or lesson_right_id is not null
);


-- ============================================================
-- 7. CANCELLATION EVENT LEDGER
--
-- lessons.status only represents CURRENT state.
--
-- This immutable table records every cancellation so:
--
-- original regular lesson
--   cancel     -> counts
--   rebook
--   cancel     -> same entitlement restored, does NOT count again
--
-- can be represented correctly.
-- ============================================================

create table public.lesson_cancellation_events (
  id uuid primary key
    default gen_random_uuid(),

  lesson_id uuid not null
    references public.lessons(id)
    on delete restrict,

  lesson_right_id uuid not null
    references public.lesson_rights(id)
    on delete restrict,

  student_id uuid not null
    references public.students(id)
    on delete restrict,

  branch_id uuid not null
    references public.branches(id)
    on delete restrict,

  origin public.lesson_cancellation_origin
    not null,

  actor_id uuid
    references public.profiles(id)
    on delete set null,

  -- Student's FIRST cancellation of an entitlement may count.
  -- Re-canceling its replacement does not.
  -- Academy cancellations never count.
  counts_toward_limit boolean
    not null,

  canceled_at timestamptz not null
    default now(),

  reason text,

  created_at timestamptz not null
    default now(),

  constraint lesson_cancellation_events_count_origin_check
    check (
      counts_toward_limit = false

      or origin =
        'student'::public.lesson_cancellation_origin
    )
);


create index lesson_cancellation_events_student_idx
on public.lesson_cancellation_events (
  student_id,
  canceled_at
);


create index lesson_cancellation_events_right_idx
on public.lesson_cancellation_events (
  lesson_right_id,
  canceled_at
);


create index lesson_cancellation_events_branch_idx
on public.lesson_cancellation_events (
  branch_id,
  canceled_at
);


create index lesson_cancellation_events_counting_idx
on public.lesson_cancellation_events (
  lesson_right_id,
  canceled_at
)
where counts_toward_limit = true;


alter table public.lesson_cancellation_events
enable row level security;


-- ============================================================
-- 8. CANCELLATION EVENT IDENTITY INTEGRITY
-- ============================================================

create or replace function public.assert_lesson_cancellation_event_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_lesson_student_id uuid;
  v_lesson_branch_id uuid;
  v_lesson_right_id uuid;

  v_right_student_id uuid;
  v_right_branch_id uuid;
begin

  select
    l.student_id,
    l.branch_id,
    l.lesson_right_id
  into
    v_lesson_student_id,
    v_lesson_branch_id,
    v_lesson_right_id
  from public.lessons l
  where l.id = new.lesson_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_LESSON_NOT_FOUND';
  end if;


  select
    r.student_id,
    r.branch_id
  into
    v_right_student_id,
    v_right_branch_id
  from public.lesson_rights r
  where r.id = new.lesson_right_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_RIGHT_NOT_FOUND';
  end if;


  if v_lesson_right_id is distinct from
     new.lesson_right_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_LESSON_RIGHT_MISMATCH';

  end if;


  if new.student_id <>
       v_lesson_student_id
     or new.student_id <>
       v_right_student_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_STUDENT_MISMATCH';

  end if;


  if new.branch_id <>
       v_lesson_branch_id
     or new.branch_id <>
       v_right_branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_BRANCH_MISMATCH';

  end if;


  if new.origin =
       'student'::public.lesson_cancellation_origin
     and new.actor_id is distinct from
         new.student_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_CANCELLATION_ACTOR_MISMATCH';

  end if;


  return new;
end;
$$;


create trigger lesson_cancellation_events_assert_integrity
before insert
on public.lesson_cancellation_events
for each row
execute function public.assert_lesson_cancellation_event_integrity();


-- ============================================================
-- 9. CANCELLATION EVENTS ARE IMMUTABLE
-- ============================================================

create or replace function public.prevent_cancellation_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message =
      'FORESTRING_CANCELLATION_EVENT_IMMUTABLE';
end;
$$;


create trigger lesson_cancellation_events_immutable
before update or delete
on public.lesson_cancellation_events
for each row
execute function public.prevent_cancellation_event_mutation();


-- ============================================================
-- 10. PRIVILEGES
-- ============================================================

revoke all
on table
  public.lesson_rights,
  public.lesson_cancellation_events
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table
  public.lesson_rights,
  public.lesson_cancellation_events
from authenticated;


grant select
on table
  public.lesson_rights,
  public.lesson_cancellation_events
to authenticated;


-- ============================================================
-- 11. LESSON RIGHTS RLS
--
-- Teacher is intentionally NOT granted raw rights access.
-- Rights are student entitlement/accounting data.
-- ============================================================

create policy lesson_rights_select
on public.lesson_rights
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


-- ============================================================
-- 12. CANCELLATION EVENT RLS
-- ============================================================

create policy lesson_cancellation_events_select
on public.lesson_cancellation_events
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


comment on table public.lesson_rights is
  'Canonical lesson entitlement ledger for regular, flex, and one-generation carryover rights.';


comment on column public.lesson_rights.duration_minutes is
  'Entitlement/default duration snapshot. One-off administrative lesson duration changes do not mutate this value.';


comment on table public.lesson_cancellation_events is
  'Immutable domain ledger of lesson cancellations used for cancellation quota calculations.';