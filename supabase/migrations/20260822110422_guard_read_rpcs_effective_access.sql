-- ============================================================
-- Forestring v3
-- Effective-access guard for maintained read RPCs
--
-- Business logic is intentionally unchanged.
-- This migration only adds the canonical actor-access gate.
-- ============================================================


-- ============================================================
-- 1. ASSIGNABLE TEACHERS
-- ============================================================

create or replace function public.get_assignable_teachers_for_student(
  p_student_id uuid
)
returns table(
  teacher_id uuid,
  display_name text,
  profile_role public.user_role
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_student_branch_id uuid;
  v_student_status public.student_status;

  v_today date;
begin
  v_actor_id :=
    (select auth.uid());


  -- Canonical current-access gate.
  perform private.require_effective_actor(
    v_actor_id
  );


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- ACTOR
  -- ==========================================================

  select
    p.role,
    p.branch_id

  into
    v_actor_role,
    v_actor_branch_id

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTOR_NOT_FOUND';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ASSIGNMENT_FORBIDDEN';

  end if;


  -- ==========================================================
  -- STUDENT
  -- ==========================================================

  select
    p.branch_id,
    s.status

  into
    v_student_branch_id,
    v_student_status

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        p_student_id

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_INACTIVE';

  end if;


  if v_actor_role =
       'manager'::public.user_role

     and v_actor_branch_id
         is distinct from
         v_student_branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_MISMATCH';

  end if;


  -- ==========================================================
  -- CANDIDATES
  -- ==========================================================

  return query

  select
    t.id,
    p.display_name,
    p.role

  from public.teachers t

  join public.profiles p
    on p.id = t.id

  where p.branch_id =
        v_student_branch_id

    and p.is_active = true

    and (
      t.withdrawal_date is null
      or t.withdrawal_date >
         v_today
    )

  order by
    lower(p.display_name),
    p.id;

end;
$$;



-- ============================================================
-- 2. LESSON-RIGHT BOOKING OPTIONS
-- ============================================================

create or replace function public.get_lesson_right_booking_options(
  p_right_id uuid,
  p_selected_date date
)
returns table(
  starts_at timestamptz,
  ends_at timestamptz,
  teacher_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_right public.lesson_rights%rowtype;

  v_semester_start date;
  v_semester_end date;

  v_assignment_teacher_id uuid;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';

  end if;


  -- Canonical current-access gate.
  perform private.require_effective_actor(
    v_actor_id
  );


  if not exists (
    select 1

    from public.profiles p

    join public.students s
      on s.id = p.id

    where p.id =
          v_actor_id

      and p.is_active = true

      and p.role =
          'student'::public.user_role

      and s.status =
          'active'::public.student_status
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';

  end if;


  -- ==========================================================
  -- RIGHT
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        p_right_id;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';

  end if;


  if v_right.student_id <>
     v_actor_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_FORBIDDEN';

  end if;


  if v_right.status <>
     'available'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE';

  end if;


  -- ==========================================================
  -- EFFECTIVE USABLE SEMESTER
  -- ==========================================================

  select
    bounds.starts_on,
    bounds.ends_on

  into
    v_semester_start,
    v_semester_end

  from private.get_effective_semester_bounds(
    v_right.branch_id,
    v_right.usable_semester_id
  ) bounds;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_FOUND';

  end if;


  if p_selected_date
     not between
       v_semester_start
       and v_semester_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_DATE_OUTSIDE_USABLE_SEMESTER';

  end if;


  -- ==========================================================
  -- ASSIGNMENT ON SELECTED DATE
  -- ==========================================================

  select a.teacher_id
  into v_assignment_teacher_id

  from public.teacher_student_assignments a

  join public.profiles teacher_profile
    on teacher_profile.id =
       a.teacher_id

  where a.student_id =
        v_right.student_id

    and a.branch_id =
        v_right.branch_id

    and a.starts_on <=
        p_selected_date

    and (
      a.ends_on is null
      or a.ends_on >=
         p_selected_date
    )

    and teacher_profile.is_active = true

    and teacher_profile.branch_id =
        v_right.branch_id

    and teacher_profile.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

  limit 1;


  if v_assignment_teacher_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_ASSIGNMENT_REQUIRED';

  end if;


  -- ==========================================================
  -- SERVER-CALCULATED CANDIDATES
  -- ==========================================================

  return query

  select
    candidate.starts_at,
    candidate.ends_at,
    candidate.teacher_id

  from private.lesson_right_slot_candidates(
    p_right_id,
    p_selected_date,
    v_actor_id
  ) candidate;

end;
$$;



-- ============================================================
-- 3. STAFF DEPARTURE BLOCKERS
-- ============================================================

create or replace function public.get_staff_departure_blockers(
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


  -- Canonical current-access gate.
  perform private.require_effective_actor(
    v_actor_id
  );


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