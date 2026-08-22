-- ============================================================
-- Forestring v3
-- Complete staff departure lifecycle
--
-- Existing source of truth:
--   public.teachers.withdrawal_date
--
-- Semantics:
--   withdrawal_date = first day the staff member may NOT work.
--
-- Therefore:
--   day before withdrawal_date -> allowed
--   withdrawal_date            -> forbidden
--   after withdrawal_date      -> forbidden
--
-- Scheduling a departure does NOT delete or rewrite existing
-- operational data. Existing future dependencies become
-- blockers and must be resolved explicitly.
-- ============================================================


-- ============================================================
-- 1. BLOCKER SUMMARY
-- ============================================================

create or replace function
private.staff_departure_blocker_summary(
  p_staff_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment_count integer;
  v_series_count integer;
  v_lesson_count integer;

  v_student_ids uuid[];
  v_lesson_ids uuid[];
begin

  if p_staff_id is null
     or p_withdrawal_date is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_CONTEXT_REQUIRED';

  end if;


  -- Any assignment still valid on or after withdrawal day.
  select
    count(*)::integer,
    array_agg(
      distinct a.student_id
    )

  into
    v_assignment_count,
    v_student_ids

  from public.teacher_student_assignments a

  where a.teacher_id =
        p_staff_id

    and (
      a.ends_on is null
      or a.ends_on >=
         p_withdrawal_date
    );


  -- Any recurring series still valid on or after withdrawal day.
  select
    count(*)::integer

  into
    v_series_count

  from public.lesson_series ls

  where ls.teacher_id =
        p_staff_id

    and (
      ls.effective_until is null
      or ls.effective_until >=
         p_withdrawal_date
    );


  -- Actual scheduled lessons are based on actual starts_at,
  -- not occurrence_at.
  select
    count(*)::integer,
    array_agg(l.id order by l.starts_at)

  into
    v_lesson_count,
    v_lesson_ids

  from public.lessons l

  where l.teacher_id =
        p_staff_id

    and l.status =
        'scheduled'::public.lesson_status

    and (
      l.starts_at
      at time zone 'Asia/Seoul'
    )::date >=
        p_withdrawal_date;


  return jsonb_build_object(
    'assignmentCount',
      coalesce(
        v_assignment_count,
        0
      ),

    'studentIds',
      coalesce(
        to_jsonb(v_student_ids),
        '[]'::jsonb
      ),

    'seriesCount',
      coalesce(
        v_series_count,
        0
      ),

    'scheduledLessonCount',
      coalesce(
        v_lesson_count,
        0
      ),

    'scheduledLessonIds',
      coalesce(
        to_jsonb(v_lesson_ids),
        '[]'::jsonb
      ),

    'canFinalize',
      coalesce(
        v_assignment_count,
        0
      ) = 0
      and
      coalesce(
        v_series_count,
        0
      ) = 0
      and
      coalesce(
        v_lesson_count,
        0
      ) = 0
  );

end;
$$;


revoke all
on function
private.staff_departure_blocker_summary(
  uuid,
  date
)
from public, anon, authenticated;



-- ============================================================
-- 2. SCHEDULE STAFF DEPARTURE
--
-- master:
--   teacher / manager
--
-- manager:
--   own-branch teacher only
--   cannot schedule self or another manager
-- ============================================================

create or replace function
public.schedule_staff_departure(
  p_staff_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_target_role public.user_role;
  v_branch_id uuid;
  v_is_active boolean;

  v_previous_date date;

  v_today date;

  v_blockers jsonb;
begin

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
  end if;


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  if p_staff_id is null
     or p_withdrawal_date is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_INPUT_REQUIRED';

  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if p_withdrawal_date <
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_DATE_IN_PAST';

  end if;


  select
    p.role,
    p.branch_id,
    p.is_active,
    t.withdrawal_date

  into
    v_target_role,
    v_branch_id,
    v_is_active,
    v_previous_date

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.id =
        p_staff_id

  for update of p, t;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_NOT_FOUND';
  end if;


  if v_target_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_NOT_STAFF';

  end if;


  if not v_is_active then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STAFF_REQUIRED';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_BRANCH_REQUIRED';
  end if;


  if v_actor_role =
     'manager'::public.user_role then

    if v_target_role <>
       'teacher'::public.user_role then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

    end if;


    if not private.manager_has_branch(
      v_branch_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;

  end if;


  -- Once the departure day has arrived, do not silently move
  -- the historical effective date.
  if v_previous_date is not null
     and v_previous_date <= v_today
     and v_previous_date <>
         p_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_ALREADY_EFFECTIVE';

  end if;


  if v_previous_date is not distinct from
     p_withdrawal_date then

    v_blockers :=
      private.staff_departure_blocker_summary(
        p_staff_id,
        p_withdrawal_date
      );


    return
      jsonb_build_object(
        'changed',
          false,

        'staffId',
          p_staff_id,

        'branchId',
          v_branch_id,

        'role',
          v_target_role,

        'withdrawalDate',
          p_withdrawal_date
      )
      ||
      v_blockers;

  end if;


  update public.teachers
  set withdrawal_date =
      p_withdrawal_date
  where id =
        p_staff_id;


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_staff_id,
    v_branch_id,
    null,
    'STAFF_DEPARTURE_SCHEDULED',
    p_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'role',
        v_target_role,

      'previousWithdrawalDate',
        v_previous_date,

      'withdrawalDate',
        p_withdrawal_date
    )
  );


  v_blockers :=
    private.staff_departure_blocker_summary(
      p_staff_id,
      p_withdrawal_date
    );


  return
    jsonb_build_object(
      'changed',
        true,

      'staffId',
        p_staff_id,

      'branchId',
        v_branch_id,

      'role',
        v_target_role,

      'previousWithdrawalDate',
        v_previous_date,

      'withdrawalDate',
        p_withdrawal_date
    )
    ||
    v_blockers;

end;
$$;



-- ============================================================
-- 3. CANCEL FUTURE DEPARTURE
-- ============================================================

create or replace function
public.cancel_staff_departure(
  p_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_target_role public.user_role;
  v_branch_id uuid;
  v_is_active boolean;
  v_withdrawal_date date;

  v_today date;
begin

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
  end if;


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  select
    p.role,
    p.branch_id,
    p.is_active,
    t.withdrawal_date

  into
    v_target_role,
    v_branch_id,
    v_is_active,
    v_withdrawal_date

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.id =
        p_staff_id

  for update of p, t;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_NOT_FOUND';
  end if;


  if v_target_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_NOT_STAFF';

  end if;


  if not v_is_active then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STAFF_REQUIRED';
  end if;


  if v_actor_role =
     'manager'::public.user_role then

    if v_target_role <>
       'teacher'::public.user_role
       or not private.manager_has_branch(
         v_branch_id
       ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

    end if;

  end if;


  if v_withdrawal_date is null then

    return jsonb_build_object(
      'changed',
        false,

      'staffId',
        p_staff_id,

      'withdrawalDate',
        null
    );

  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_withdrawal_date <=
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_ALREADY_EFFECTIVE';

  end if;


  update public.teachers
  set withdrawal_date =
      null
  where id =
        p_staff_id;


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_staff_id,
    v_branch_id,
    null,
    'STAFF_DEPARTURE_CANCELED',
    v_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'role',
        v_target_role,

      'canceledWithdrawalDate',
        v_withdrawal_date
    )
  );


  return jsonb_build_object(
    'changed',
      true,

    'staffId',
      p_staff_id,

    'previousWithdrawalDate',
      v_withdrawal_date,

    'withdrawalDate',
      null
  );

end;
$$;



-- ============================================================
-- 4. GET BLOCKERS
-- ============================================================

create or replace function
public.get_staff_departure_blockers(
  p_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_target_role public.user_role;
  v_branch_id uuid;
  v_withdrawal_date date;
begin

  v_actor_id :=
    auth.uid();


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  select
    p.role,
    p.branch_id,
    t.withdrawal_date

  into
    v_target_role,
    v_branch_id,
    v_withdrawal_date

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.id =
        p_staff_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_NOT_FOUND';
  end if;


  if v_actor_role =
     'manager'::public.user_role
     and (
       v_target_role <>
       'teacher'::public.user_role

       or not private.manager_has_branch(
         v_branch_id
       )
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  if v_withdrawal_date is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_NOT_SCHEDULED';
  end if;


  return
    jsonb_build_object(
      'staffId',
        p_staff_id,

      'branchId',
        v_branch_id,

      'role',
        v_target_role,

      'withdrawalDate',
        v_withdrawal_date
    )
    ||
    private.staff_departure_blocker_summary(
      p_staff_id,
      v_withdrawal_date
    );

end;
$$;



-- ============================================================
-- 5. FINALIZE DEPARTURE
--
-- Nothing is automatically deleted or reassigned here.
-- All future dependencies must already be resolved.
-- ============================================================

create or replace function
public.finalize_staff_departure(
  p_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_target_role public.user_role;
  v_branch_id uuid;
  v_is_active boolean;
  v_withdrawal_date date;

  v_today date;

  v_blockers jsonb;
begin

  v_actor_id :=
    auth.uid();


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  select
    p.role,
    p.branch_id,
    p.is_active,
    t.withdrawal_date

  into
    v_target_role,
    v_branch_id,
    v_is_active,
    v_withdrawal_date

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.id =
        p_staff_id

  for update of p, t;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_NOT_FOUND';
  end if;


  if v_target_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_NOT_STAFF';

  end if;


  if v_actor_role =
     'manager'::public.user_role
     and (
       v_target_role <>
       'teacher'::public.user_role

       or not private.manager_has_branch(
         v_branch_id
       )
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_FORBIDDEN';

  end if;


  if v_withdrawal_date is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_NOT_SCHEDULED';
  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_withdrawal_date >
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_NOT_EFFECTIVE_YET';

  end if;


  -- Idempotent completed state.
  if not v_is_active then

    return jsonb_build_object(
      'changed',
        false,

      'staffId',
        p_staff_id,

      'withdrawalDate',
        v_withdrawal_date,

      'isActive',
        false
    );

  end if;


  v_blockers :=
    private.staff_departure_blocker_summary(
      p_staff_id,
      v_withdrawal_date
    );


  if coalesce(
       (
         v_blockers
         ->> 'canFinalize'
       )::boolean,
       false
     ) <> true then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_BLOCKED',
      detail =
        v_blockers::text;

  end if;


  update public.profiles
  set is_active =
      false
  where id =
        p_staff_id;


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_staff_id,
    v_branch_id,
    null,
    'STAFF_DEPARTURE_FINALIZED',
    v_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'role',
        v_target_role,

      'withdrawalDate',
        v_withdrawal_date
    )
  );


  return
    jsonb_build_object(
      'changed',
        true,

      'staffId',
        p_staff_id,

      'branchId',
        v_branch_id,

      'role',
        v_target_role,

      'withdrawalDate',
        v_withdrawal_date,

      'isActive',
        false
    )
    ||
    v_blockers;

end;
$$;



-- ============================================================
-- 6. HARD GUARD: ASSIGNMENTS
--
-- Scheduling departure may leave EXISTING rows crossing the
-- boundary temporarily.
--
-- But after that point nobody may INSERT/UPDATE an assignment
-- that still uses that teacher on or after withdrawal_date.
-- ============================================================

create or replace function
public.assert_assignment_before_teacher_withdrawal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal_date date;
begin

  select t.withdrawal_date
  into v_withdrawal_date

  from public.teachers t

  where t.id =
        new.teacher_id;


  if v_withdrawal_date is null then
    return new;
  end if;


  if new.starts_on >=
     v_withdrawal_date

     or new.ends_on is null

     or new.ends_on >=
        v_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ASSIGNMENT_ON_OR_AFTER_TEACHER_WITHDRAWAL';

  end if;


  return new;

end;
$$;


drop trigger if exists
teacher_student_assignments_assert_teacher_withdrawal
on public.teacher_student_assignments;


create trigger
teacher_student_assignments_assert_teacher_withdrawal
before insert or update of
  teacher_id,
  starts_on,
  ends_on
on public.teacher_student_assignments
for each row
execute function
public.assert_assignment_before_teacher_withdrawal();



-- ============================================================
-- 7. HARD GUARD: LESSON SERIES
-- ============================================================

create or replace function
public.assert_series_before_teacher_withdrawal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal_date date;
begin

  select t.withdrawal_date
  into v_withdrawal_date

  from public.teachers t

  where t.id =
        new.teacher_id;


  if v_withdrawal_date is null then
    return new;
  end if;


  if new.effective_from >=
     v_withdrawal_date

     or new.effective_until is null

     or new.effective_until >=
        v_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SERIES_ON_OR_AFTER_TEACHER_WITHDRAWAL';

  end if;


  return new;

end;
$$;


drop trigger if exists
lesson_series_assert_teacher_withdrawal
on public.lesson_series;


create trigger
lesson_series_assert_teacher_withdrawal
before insert or update of
  teacher_id,
  effective_from,
  effective_until
on public.lesson_series
for each row
execute function
public.assert_series_before_teacher_withdrawal();



-- ============================================================
-- 8. HARD GUARD: ACTUAL LESSON
--
-- CANCELED lessons are historical facts and may remain after
-- withdrawal.
--
-- Only a scheduled lesson is forbidden on/after the boundary.
-- ============================================================

create or replace function
public.assert_lesson_before_teacher_withdrawal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal_date date;
  v_lesson_date date;
begin

  if new.status <>
     'scheduled'::public.lesson_status then

    return new;

  end if;


  select t.withdrawal_date
  into v_withdrawal_date

  from public.teachers t

  where t.id =
        new.teacher_id;


  if v_withdrawal_date is null then
    return new;
  end if;


  v_lesson_date :=
    (
      new.starts_at
      at time zone 'Asia/Seoul'
    )::date;


  if v_lesson_date >=
     v_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_ON_OR_AFTER_TEACHER_WITHDRAWAL';

  end if;


  return new;

end;
$$;


drop trigger if exists
lessons_assert_teacher_withdrawal_boundary
on public.lessons;


create trigger
lessons_assert_teacher_withdrawal_boundary
before insert or update of
  teacher_id,
  starts_at,
  status
on public.lessons
for each row
execute function
public.assert_lesson_before_teacher_withdrawal();



-- ============================================================
-- 9. DO NOT CHANGE STAFF ROLE WHILE DEPARTURE IS PENDING
--
-- Cancel the departure first, then change teacher <-> manager.
-- This avoids role changes changing who is allowed to manage
-- an already-scheduled departure.
-- ============================================================

create or replace function
public.assert_staff_role_change_without_pending_departure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin

  if new.role is not distinct from
     old.role then

    return new;

  end if;


  if exists (
    select 1

    from public.teachers t

    where t.id =
          old.id

      and t.withdrawal_date
          is not null
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STAFF_DEPARTURE_PENDING';

  end if;


  return new;

end;
$$;


drop trigger if exists
profiles_assert_staff_role_change_departure
on public.profiles;


create trigger
profiles_assert_staff_role_change_departure
before update of role
on public.profiles
for each row
execute function
public.assert_staff_role_change_without_pending_departure();



-- ============================================================
-- 10. PRIVILEGES
-- ============================================================

revoke all
on function
public.schedule_staff_departure(uuid, date),
public.cancel_staff_departure(uuid),
public.get_staff_departure_blockers(uuid),
public.finalize_staff_departure(uuid)
from public, anon, authenticated;


grant execute
on function
public.schedule_staff_departure(uuid, date),
public.cancel_staff_departure(uuid),
public.get_staff_departure_blockers(uuid),
public.finalize_staff_departure(uuid)
to authenticated;


revoke all
on function
public.assert_assignment_before_teacher_withdrawal(),
public.assert_series_before_teacher_withdrawal(),
public.assert_lesson_before_teacher_withdrawal(),
public.assert_staff_role_change_without_pending_departure()
from public, anon, authenticated;