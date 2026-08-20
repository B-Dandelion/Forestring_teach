-- ============================================================
-- Forestring v3
-- Flex semester base-right materialization
--
-- Calendar activation policy is intentionally NOT handled here.
--
-- This RPC only materializes rights for an already ACTIVE
-- flex semester plan.
-- ============================================================


-- ============================================================
-- MATERIALIZE FLEX BASE RIGHTS
--
-- Properties:
--
-- - master: any branch
-- - manager: own branch only
-- - student plan must be ACTIVE
-- - plan must be FLEX
-- - count + duration must already be configured
-- - creates exactly N base rights
-- - idempotent
-- - does not touch existing reserved/consumed rights
-- - does not perform current-semester corrections
--
-- Current-semester corrections will later use a separate,
-- master-only RPC.
-- ============================================================

create or replace function public.materialize_flex_base_rights(
  p_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;

  v_plan public.student_semester_plans%rowtype;

  v_student_branch_id uuid;
  v_student_active boolean;
  v_student_status public.student_status;

  v_inserted_count integer;
  v_total_count integer;
  v_invalid_count integer;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id := auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.is_active = true
      and p.role in (
        'master'::public.user_role,
        'manager'::public.user_role
      )
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';

  end if;


  -- ==========================================================
  -- LOCK PLAN
  -- ==========================================================

  select *
  into v_plan
  from public.student_semester_plans sp
  where sp.id = p_plan_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_PLAN_NOT_FOUND';
  end if;


  -- ==========================================================
  -- MANAGER BRANCH PERMISSION
  -- ==========================================================

  if (
    select p.role
    from public.profiles p
    where p.id = v_actor_id
  ) = 'manager'::public.user_role
  then

    if not private.manager_has_branch(
      v_plan.branch_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;

  end if;


  -- ==========================================================
  -- PLAN VALIDATION
  -- ==========================================================

  if v_plan.student_type_snapshot <>
     'flex'::public.student_type then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FLEX_PLAN_REQUIRED';

  end if;


  if v_plan.status <>
     'active'::public.student_semester_plan_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_SEMESTER_PLAN_REQUIRED';

  end if;


  if v_plan.flex_base_right_count is null
     or v_plan.flex_duration_minutes is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';

  end if;


  -- ==========================================================
  -- STUDENT CURRENT STATE
  --
  -- An ACTIVE plan must belong to the student's current branch.
  -- Future branch-transfer plans will remain PLANNED until the
  -- explicit transfer/activation transaction occurs.
  -- ==========================================================

  select
    p.branch_id,
    p.is_active,
    s.status
  into
    v_student_branch_id,
    v_student_active,
    v_student_status
  from public.students s
  join public.profiles p
    on p.id = s.id
  where s.id = v_plan.student_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if not v_student_active
     or v_student_status <>
        'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';

  end if;


  if v_student_branch_id is distinct from
     v_plan.branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_PLAN_BRANCH_MISMATCH';

  end if;


  -- ==========================================================
  -- EXISTING RIGHTS MUST MATCH PLAN
  --
  -- This function is only for initial/idempotent materialization.
  -- It must never silently "correct" an already materialized
  -- semester.
  --
  -- Current-semester correction gets its own master-only RPC.
  -- ==========================================================

  select count(*)::integer
  into v_invalid_count
  from public.lesson_rights r
  where r.student_id =
        v_plan.student_id

    and r.source_semester_id =
        v_plan.semester_id

    and r.origin =
        'flex_base'::public.lesson_right_origin

    and (
      r.branch_id <>
        v_plan.branch_id

      or r.usable_semester_id <>
        v_plan.semester_id

      or r.duration_minutes <>
        v_plan.flex_duration_minutes

      or r.sequence_no >
        v_plan.flex_base_right_count
    );


  if v_invalid_count > 0 then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FLEX_RIGHTS_PLAN_MISMATCH';

  end if;


  -- ==========================================================
  -- IDEMPOTENT INSERT
  --
  -- Unique index:
  --
  -- student_id
  -- + source_semester_id
  -- + sequence_no
  -- WHERE origin = flex_base
  --
  -- prevents duplicates.
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    source_right_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    carryover_count,
    created_by
  )
  select
    v_plan.student_id,
    v_plan.branch_id,
    v_plan.semester_id,
    v_plan.semester_id,
    null,
    null,
    'flex_base'::public.lesson_right_origin,
    sequence_no,
    v_plan.flex_duration_minutes,
    'available'::public.lesson_right_status,
    0,
    v_actor_id

  from generate_series(
    1,
    v_plan.flex_base_right_count
  ) as sequence_no

  on conflict do nothing;


  get diagnostics
    v_inserted_count = row_count;


  -- ==========================================================
  -- FINAL EXACT-N ASSERTION
  -- ==========================================================

  select count(*)::integer
  into v_total_count
  from public.lesson_rights r
  where r.student_id =
        v_plan.student_id

    and r.source_semester_id =
        v_plan.semester_id

    and r.origin =
        'flex_base'::public.lesson_right_origin;


  if v_total_count <>
     v_plan.flex_base_right_count then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FLEX_RIGHT_COUNT_MISMATCH';

  end if;


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'planId',
    v_plan.id,

    'studentId',
    v_plan.student_id,

    'semesterId',
    v_plan.semester_id,

    'branchId',
    v_plan.branch_id,

    'baseRightCount',
    v_plan.flex_base_right_count,

    'durationMinutes',
    v_plan.flex_duration_minutes,

    'insertedCount',
    v_inserted_count,

    'totalCount',
    v_total_count
  );

end;
$$;


-- ============================================================
-- FUNCTION PRIVILEGES
-- ============================================================

revoke all
on function public.materialize_flex_base_rights(uuid)
from public, anon;


grant execute
on function public.materialize_flex_base_rights(uuid)
to authenticated;


comment on function public.materialize_flex_base_rights(uuid) is
  'Idempotently creates exactly N flex_base lesson rights for an already-active flex semester plan. Does not activate semesters or perform current-semester corrections.';