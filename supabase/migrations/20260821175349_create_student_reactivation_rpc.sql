-- ============================================================
-- Forestring v3
-- Student reactivation
--
-- Reactivation restores the EXISTING student identity.
--
-- It intentionally does NOT:
--   - create a new auth user
--   - change student_type
--   - revive lesson rights
--   - revive teacher assignments
--   - revive regular schedules
--   - create semester plans
--   - create lessons
--
-- Those are explicit enrollment configuration actions.
-- ============================================================


create or replace function public.reactivate_student(
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_branch_id uuid;
  v_profile_role public.user_role;
  v_profile_active boolean;

  v_student_status public.student_status;
  v_student_type public.student_type;
  v_withdrawal_date date;

  v_today date;

  v_residual_active_right_count integer := 0;
begin

  -- ==========================================================
  -- 1. AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_REACTIVATION_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 2. LOCK STUDENT + PROFILE
  -- ==========================================================

  select
    p.branch_id,
    p.role,
    p.is_active,
    s.status,
    s.student_type,
    s.withdrawal_date

  into
    v_branch_id,
    v_profile_role,
    v_profile_active,
    v_student_status,
    v_student_type,
    v_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id =
       s.id

  where s.id =
        p_student_id

  for update of s, p;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_profile_role <>
     'student'::public.user_role then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROFILE_NOT_STUDENT';

  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- 3. BRANCH MUST STILL EXIST + BE ACTIVE
  -- ==========================================================

  if not exists (
    select 1

    from public.branches b

    where b.id =
          v_branch_id

      and b.is_active = true
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_ACTIVE';

  end if;


  -- ==========================================================
  -- 4. MANAGER OWN BRANCH ONLY
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role

     and not private.manager_has_branch(
       v_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 5. IDEMPOTENT SECOND CALL
  -- ==========================================================

  if v_student_status =
       'active'::public.student_status

     and v_profile_active = true

     and v_withdrawal_date is null then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'branchId',
        v_branch_id,

      'studentType',
        v_student_type,

      'requiresEnrollmentSetup',
        true
    );

  end if;


  -- ==========================================================
  -- 6. VALID WITHDRAWN STATE REQUIRED
  -- ==========================================================

  if v_student_status <>
     'withdrawn'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_WITHDRAWN';

  end if;


  if v_withdrawal_date is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWN_STUDENT_DATE_REQUIRED';

  end if;


  if v_profile_active = true then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWN_PROFILE_STILL_ACTIVE';

  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- 7. DEFENSIVE RIGHT CLEANUP
  --
  -- finalize_student_withdrawal() should already have revoked
  -- every remaining available/reserved right.
  --
  -- Do NOT revive anything here.
  -- If legacy/manual state left an active entitlement behind,
  -- revoke it before the student becomes active again.
  -- ==========================================================

  update public.lesson_rights r

  set
    status =
      'revoked'::public.lesson_right_status,

    revoked_at =
      coalesce(
        r.revoked_at,
        pg_catalog.now()
      )

  where r.student_id =
        p_student_id

    and r.status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );


  get diagnostics
    v_residual_active_right_count =
      row_count;


  -- ==========================================================
  -- 8. REACTIVATE EXISTING IDENTITY
  --
  -- student_type is intentionally untouched.
  -- ==========================================================

  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        p_student_id;


  update public.profiles
  set
    is_active =
      true

  where id =
        p_student_id;


  -- ==========================================================
  -- 9. AUDIT
  -- ==========================================================

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
    p_student_id,
    v_branch_id,
    null,
    'STUDENT_REACTIVATED',
    v_today,
    v_actor_id,

    jsonb_build_object(
      'previousWithdrawalDate',
        v_withdrawal_date,

      'studentType',
        v_student_type,

      'residualActiveRightsRevoked',
        v_residual_active_right_count,

      'teacherAssignmentRestored',
        false,

      'regularScheduleRestored',
        false,

      'lessonRightsRestored',
        false
    )
  );


  -- ==========================================================
  -- 10. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'branchId',
      v_branch_id,

    'studentType',
      v_student_type,

    'previousWithdrawalDate',
      v_withdrawal_date,

    'residualActiveRightsRevoked',
      v_residual_active_right_count,

    'requiresEnrollmentSetup',
      true
  );

end;
$$;


revoke all
on function public.reactivate_student(
  uuid
)
from public, anon;


grant execute
on function public.reactivate_student(
  uuid
)
to authenticated;


comment on function public.reactivate_student(
  uuid
) is
  'Reactivates an existing withdrawn student identity without creating a new UUID or reviving historical assignments, schedules, lessons or lesson rights. Student type is preserved; enrollment configuration is performed separately.';