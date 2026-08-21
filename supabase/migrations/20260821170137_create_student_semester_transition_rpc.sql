-- ============================================================
-- Forestring v3
-- Atomic student semester transition
--
-- source semester:
--   finalize rights / carryover
--
-- target semester:
--   apply student type snapshot
--   activate/materialize target plan
--
-- Regular -> Flex:
--   close previous logical regular schedule slots at boundary
--
-- Branch transfer is intentionally NOT handled here.
-- ============================================================


create or replace function public.transition_student_semester(
  p_source_plan_id uuid,
  p_target_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_source_plan public.student_semester_plans%rowtype;
  v_target_plan public.student_semester_plans%rowtype;

  v_current_student_type public.student_type;
  v_student_status public.student_status;
  v_student_branch_id uuid;

  v_source_start date;
  v_source_end date;

  v_target_start date;
  v_target_end date;

  v_today date;

  v_finalization_result jsonb;
  v_activation_result jsonb;

  v_type_changed boolean := false;

  v_closed_slot_count integer := 0;
  v_closed_series_count integer := 0;

  v_changed boolean := false;
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

  where p.id = v_actor_id
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
      message =
        'FORESTRING_SEMESTER_TRANSITION_FORBIDDEN';

  end if;


  if p_source_plan_id is null
     or p_target_plan_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_TRANSITION_PLAN_REQUIRED';

  end if;


  if p_source_plan_id =
     p_target_plan_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_TRANSITION_SAME_PLAN';

  end if;


  -- ==========================================================
  -- 2. LOCK SOURCE
  -- ==========================================================

  select *
  into v_source_plan

  from public.student_semester_plans sp

  where sp.id =
        p_source_plan_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_SEMESTER_PLAN_NOT_FOUND';
  end if;


  -- ==========================================================
  -- 3. LOCK TARGET
  -- ==========================================================

  select *
  into v_target_plan

  from public.student_semester_plans sp

  where sp.id =
        p_target_plan_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
  end if;


  -- ==========================================================
  -- 4. SAME STUDENT / SAME BRANCH
  --
  -- Branch transition will be its own dedicated RPC.
  -- ==========================================================

  if v_source_plan.student_id <>
     v_target_plan.student_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_TRANSITION_STUDENT_MISMATCH';

  end if;


  if v_source_plan.branch_id <>
     v_target_plan.branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BRANCH_TRANSFER_REQUIRES_DEDICATED_FLOW';

  end if;


  if v_target_plan.status =
     'completed'::public.student_semester_plan_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_SEMESTER_ALREADY_COMPLETED';

  end if;


  -- ==========================================================
  -- 5. LOCK CURRENT STUDENT STATE
  -- ==========================================================

  select
    s.student_type,
    s.status,
    p.branch_id

  into
    v_current_student_type,
    v_student_status,
    v_student_branch_id

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        v_source_plan.student_id

    and p.is_active = true

  for update of s;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_INACTIVE';

  end if;


  if v_student_branch_id is distinct from
     v_source_plan.branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_BRANCH_MISMATCH';

  end if;


  -- ==========================================================
  -- 6. MANAGER BRANCH
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_source_plan.branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 7. EFFECTIVE SEMESTER BOUNDS
  -- ==========================================================

  select
    e.starts_on,
    e.ends_on

  into
    v_source_start,
    v_source_end

  from private.get_effective_semester_bounds(
    v_source_plan.branch_id,
    v_source_plan.semester_id
  ) e;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_SEMESTER_NOT_FOUND';
  end if;


  select
    e.starts_on,
    e.ends_on

  into
    v_target_start,
    v_target_end

  from private.get_effective_semester_bounds(
    v_target_plan.branch_id,
    v_target_plan.semester_id
  ) e;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_SEMESTER_NOT_FOUND';
  end if;


  if v_target_start <>
     v_source_end + 1 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TARGET_SEMESTER_NOT_CONSECUTIVE';

  end if;


  -- ==========================================================
  -- 8. BOUNDARY MUST HAVE ARRIVED
  -- ==========================================================

  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_today <
     v_target_start then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_TRANSITION_NOT_READY';

  end if;


  -- ==========================================================
  -- 9. FINALIZE SOURCE
  --
  -- Existing RPC is idempotent.
  --
  -- This also creates permitted carryovers into target.
  -- ==========================================================

  v_finalization_result :=
    public.finalize_student_semester_rights(
      v_source_plan.id,
      v_target_plan.id
    );


  if coalesce(
    (
      v_finalization_result
      ->> 'changed'
    )::boolean,
    false
  ) then

    v_changed := true;

  end if;


  -- ==========================================================
  -- 10. REGULAR -> FLEX
  --
  -- The old logical regular schedules end with the source
  -- semester.
  --
  -- Historical rows remain.
  -- ==========================================================

  if v_source_plan.student_type_snapshot =
       'regular'::public.student_type

     and v_target_plan.student_type_snapshot =
       'flex'::public.student_type then

    -- Close series versions that were actually active through
    -- the source boundary.
    update public.lesson_series ls
    set
      effective_until =
        v_source_end

    where ls.student_id =
          v_source_plan.student_id

      and ls.branch_id =
          v_source_plan.branch_id

      and ls.schedule_slot_id in (
        select rs.id

        from public.regular_schedule_slots rs

        where rs.student_id =
              v_source_plan.student_id

          and rs.branch_id =
              v_source_plan.branch_id

          and rs.starts_on <=
              v_source_end

          and (
            rs.ends_on is null
            or rs.ends_on >
               v_source_end
          )
      )

      and ls.effective_from <=
          v_source_end

      and (
        ls.effective_until is null
        or ls.effective_until >
           v_source_end
      );


    get diagnostics
      v_closed_series_count = row_count;


    update public.regular_schedule_slots rs
    set
      ends_on =
        v_source_end

    where rs.student_id =
          v_source_plan.student_id

      and rs.branch_id =
          v_source_plan.branch_id

      and rs.starts_on <=
          v_source_end

      and (
        rs.ends_on is null
        or rs.ends_on >
           v_source_end
      );


    get diagnostics
      v_closed_slot_count = row_count;


    if v_closed_series_count > 0
       or v_closed_slot_count > 0 then

      v_changed := true;

    end if;

  end if;


  -- ==========================================================
  -- 11. APPLY CURRENT STUDENT TYPE
  --
  -- Until this exact boundary operation,
  -- students.student_type represented the old/current type.
  -- ==========================================================

  if v_current_student_type <>
     v_target_plan.student_type_snapshot then

    update public.students
    set
      student_type =
        v_target_plan.student_type_snapshot

    where id =
          v_source_plan.student_id;


    v_type_changed :=
      true;

    v_changed :=
      true;

  end if;


  -- ==========================================================
  -- 12. ACTIVATE TARGET
  --
  -- Existing RPC validates:
  --
  -- Flex:
  --   configured N + duration
  --
  -- Regular:
  --   logical slots
  --   series
  --   work hours
  --   blocks
  --   closures
  --   exact four occurrences
  --
  -- If ANY validation fails, this whole outer transaction
  -- rolls back, including source finalization and type change.
  -- ==========================================================

  v_activation_result :=
    public.activate_student_semester_plan(
      v_target_plan.id
    );


  if coalesce(
    (
      v_activation_result
      ->> 'changed'
    )::boolean,
    false
  ) then

    v_changed :=
      true;

  end if;


  -- ==========================================================
  -- 13. AUDIT
  --
  -- Only create the high-level transition event if this call
  -- actually changed anything.
  --
  -- finalize / activate already write their own detailed
  -- audit events.
  -- ==========================================================

  if v_changed then

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
      v_source_plan.student_id,

      v_source_plan.branch_id,

      v_target_plan.semester_id,

      'STUDENT_SEMESTER_TRANSITIONED',

      v_target_start,

      v_actor_id,

      jsonb_build_object(
        'sourcePlanId',
          v_source_plan.id,

        'targetPlanId',
          v_target_plan.id,

        'sourceSemesterId',
          v_source_plan.semester_id,

        'targetSemesterId',
          v_target_plan.semester_id,

        'previousStudentType',
          v_source_plan.student_type_snapshot,

        'targetStudentType',
          v_target_plan.student_type_snapshot,

        'studentTypeChanged',
          v_type_changed,

        'closedRegularSlotCount',
          v_closed_slot_count,

        'closedRegularSeriesCount',
          v_closed_series_count,

        'finalization',
          v_finalization_result,

        'activation',
          v_activation_result
      )
    );

  end if;


  -- ==========================================================
  -- 14. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      v_changed,

    'studentId',
      v_source_plan.student_id,

    'sourcePlanId',
      v_source_plan.id,

    'targetPlanId',
      v_target_plan.id,

    'effectiveOn',
      v_target_start,

    'previousStudentType',
      v_source_plan.student_type_snapshot,

    'studentType',
      v_target_plan.student_type_snapshot,

    'studentTypeChanged',
      v_type_changed,

    'closedRegularSlotCount',
      v_closed_slot_count,

    'closedRegularSeriesCount',
      v_closed_series_count,

    'finalization',
      v_finalization_result,

    'activation',
      v_activation_result
  );

end;
$$;


revoke all
on function public.transition_student_semester(
  uuid,
  uuid
)
from public, anon;


grant execute
on function public.transition_student_semester(
  uuid,
  uuid
)
to authenticated;


comment on function public.transition_student_semester(
  uuid,
  uuid
) is
  'Atomically transitions one active student between consecutive semester plans: finalizes source entitlements/carryovers, applies the target student type at the semester boundary, closes obsolete regular schedules when moving regular-to-flex, and activates/materializes the target plan. Branch transfer is intentionally handled separately.';