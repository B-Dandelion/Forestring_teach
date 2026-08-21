-- ============================================================
-- Forestring v3
-- Finalize one student's semester entitlement lifecycle
--
-- Atomic:
--
--   reserved past lessons -> consumed
--   eligible available base rights -> carryover
--   all remaining available base rights -> expired
--   source semester plan -> completed
--
-- Flutter never decides which rights are carried.
-- ============================================================


create or replace function public.finalize_student_semester_rights(
  p_source_plan_id uuid,
  p_target_plan_id uuid default null
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

  v_source_start date;
  v_source_end date;

  v_target_start date;
  v_target_end date;

  v_boundary_date date;
  v_boundary_at timestamptz;

  v_carryover_cap integer := 0;

  v_consumed_count integer := 0;
  v_carryover_count integer := 0;
  v_expired_count integer := 0;

  v_existing_carryovers integer := 0;

  v_candidate record;
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
      message = 'FORESTRING_SEMESTER_FINALIZATION_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 2. LOCK SOURCE PLAN
  -- ==========================================================

  select *
  into v_source_plan

  from public.student_semester_plans sp

  where sp.id = p_source_plan_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SOURCE_SEMESTER_PLAN_NOT_FOUND';
  end if;


  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_source_plan.branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 3. EFFECTIVE SOURCE SEMESTER
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
      message = 'FORESTRING_SOURCE_SEMESTER_NOT_FOUND';
  end if;


  -- ==========================================================
  -- 4. OPTIONAL TARGET PLAN
  --
  -- NULL:
  --   finish semester with NO carryover
  --
  -- Present:
  --   target must be the immediately following semester.
  -- ==========================================================

  if p_target_plan_id is not null then

    select *
    into v_target_plan

    from public.student_semester_plans sp

    where sp.id = p_target_plan_id

    for update;


    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
    end if;


    if v_target_plan.student_id <>
       v_source_plan.student_id then

      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_TARGET_PLAN_STUDENT_MISMATCH';

    end if;


    -- Branch transfer will later be handled by its own
    -- dedicated boundary transaction.
    if v_target_plan.branch_id <>
       v_source_plan.branch_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_CARRYOVER_BRANCH_TRANSFER_REQUIRES_DEDICATED_FLOW';

    end if;


    if v_actor_role =
       'manager'::public.user_role
       and not private.manager_has_branch(
         v_target_plan.branch_id
       ) then

      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;


    if v_target_plan.status =
       'completed'::public.student_semester_plan_status then

      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_TARGET_SEMESTER_ALREADY_COMPLETED';

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
        message = 'FORESTRING_TARGET_SEMESTER_NOT_FOUND';
    end if;


    if v_target_start <>
       v_source_end + 1 then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_TARGET_SEMESTER_NOT_CONSECUTIVE';

    end if;


    v_boundary_date :=
      v_target_start;

  else

    v_boundary_date :=
      v_source_end + 1;

  end if;


  -- ==========================================================
  -- 5. DO NOT FINALIZE BEFORE SEMESTER IS OVER
  -- ==========================================================

  if (
    pg_catalog.now()
    at time zone 'Asia/Seoul'
  )::date <
     v_boundary_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_READY_FOR_FINALIZATION';

  end if;


  v_boundary_at :=
    (
      v_boundary_date::timestamp
      at time zone 'Asia/Seoul'
    );


  -- ==========================================================
  -- 6. IDEMPOTENCY
  -- ==========================================================

  if v_source_plan.status =
     'completed'::public.student_semester_plan_status then

    if p_target_plan_id is not null then

      select count(*)::integer
      into v_existing_carryovers

      from public.lesson_rights r

      where r.student_id =
            v_source_plan.student_id

        and r.origin =
            'carryover'::public.lesson_right_origin

        and r.usable_semester_id =
            v_target_plan.semester_id

        and exists (
          select 1

          from public.lesson_rights source_right

          where source_right.id =
                r.source_right_id

            and source_right.source_semester_id =
                v_source_plan.semester_id
        );

    end if;


    return jsonb_build_object(
      'changed', false,
      'sourcePlanId', v_source_plan.id,
      'targetPlanId', p_target_plan_id,
      'carryoverCreated', v_existing_carryovers,
      'status', 'completed'
    );

  end if;


  if v_source_plan.status <>
     'active'::public.student_semester_plan_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_SEMESTER_PLAN_NOT_ACTIVE';

  end if;


  -- ==========================================================
  -- 7. CARRYOVER CAP
  -- ==========================================================

  if p_target_plan_id is null then

    v_carryover_cap := 0;


  elsif v_source_plan.student_type_snapshot =
        'regular'::public.student_type then

    -- Regular:
    -- maximum ONE extra carried entitlement per student.
    v_carryover_cap := 1;


  elsif v_source_plan.student_type_snapshot =
        'flex'::public.student_type then

    if v_source_plan.flex_base_right_count is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_FLEX_SEMESTER_PLAN_CONFIGURATION_REQUIRED';
    end if;


    v_carryover_cap :=
      floor(
        v_source_plan.flex_base_right_count::numeric
        / 4
      )::integer;


  else

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_UNSUPPORTED_STUDENT_TYPE';

  end if;


  -- ==========================================================
  -- 8. RESERVED RIGHTS MUST HAVE A VALID FINISHED LESSON
  --
  -- A staff one-off edit could theoretically move a source
  -- lesson into the NEXT semester.
  --
  -- Do not silently consume/finalize such a case.
  -- ==========================================================

  if exists (
    select 1

    from public.lesson_rights r

    join public.lessons l
      on l.lesson_right_id = r.id

    where r.student_id =
          v_source_plan.student_id

      and r.source_semester_id =
          v_source_plan.semester_id

      and r.origin in (
        'regular_base'::public.lesson_right_origin,
        'flex_base'::public.lesson_right_origin
      )

      and r.status =
          'reserved'::public.lesson_right_status

      and l.status =
          'scheduled'::public.lesson_status

      and l.starts_at >=
          v_boundary_at
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_SEMESTER_HAS_FUTURE_RESERVED_LESSON';

  end if;


  -- Reserved must correspond to one scheduled lesson that has
  -- already occurred before the target semester boundary.
  if exists (
    select 1

    from public.lesson_rights r

    where r.student_id =
          v_source_plan.student_id

      and r.source_semester_id =
          v_source_plan.semester_id

      and r.origin in (
        'regular_base'::public.lesson_right_origin,
        'flex_base'::public.lesson_right_origin
      )

      and r.status =
          'reserved'::public.lesson_right_status

      and not exists (
        select 1

        from public.lessons l

        where l.lesson_right_id = r.id

          and l.status =
              'scheduled'::public.lesson_status

          and l.starts_at <
              v_boundary_at
      )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SOURCE_RIGHT_RESERVATION_UNRESOLVED';

  end if;


  -- ==========================================================
  -- 9. RESERVED -> CONSUMED
  --
  -- A scheduled lesson that remained scheduled through the
  -- semester boundary has spent its entitlement.
  -- ==========================================================

  update public.lesson_rights r
  set
    status =
      'consumed'::public.lesson_right_status,

    consumed_at =
      coalesce(
        r.consumed_at,
        pg_catalog.now()
      )

  from public.lessons l

  where l.lesson_right_id =
        r.id

    and r.student_id =
        v_source_plan.student_id

    and r.source_semester_id =
        v_source_plan.semester_id

    and r.origin in (
      'regular_base'::public.lesson_right_origin,
      'flex_base'::public.lesson_right_origin
    )

    and r.status =
        'reserved'::public.lesson_right_status

    and l.status =
        'scheduled'::public.lesson_status

    and l.starts_at <
        v_boundary_at;


  get diagnostics
    v_consumed_count = row_count;


  -- ==========================================================
  -- 10. MATERIALIZE CARRYOVERS
  --
  -- Eligibility:
  --   source BASE right
  --   still AVAILABLE at semester close
  --
  -- Priority:
  --
  --   1. rights with cancellation history
  --   2. oldest cancellation first
  --   3. sequence_no
  --   4. id
  --
  -- This means flex cancellation obligations are preserved
  -- before never-booked flex rights when the cap is exceeded.
  -- ==========================================================

  if p_target_plan_id is not null
     and v_carryover_cap > 0 then

    for v_candidate in

      select
        r.id,
        r.student_id,
        r.source_semester_id,
        r.sequence_no,
        r.duration_minutes,

        cancellation.first_canceled_at

      from public.lesson_rights r

      left join lateral (
        select
          min(e.canceled_at)
            as first_canceled_at

        from public.lesson_cancellation_events e

        where e.lesson_right_id =
              r.id
      ) cancellation
        on true

      where r.student_id =
            v_source_plan.student_id

        and r.source_semester_id =
            v_source_plan.semester_id

        and r.status =
            'available'::public.lesson_right_status

        and r.carryover_count = 0

        and (
          (
            v_source_plan.student_type_snapshot =
              'regular'::public.student_type

            and r.origin =
              'regular_base'::public.lesson_right_origin
          )

          or

          (
            v_source_plan.student_type_snapshot =
              'flex'::public.student_type

            and r.origin =
              'flex_base'::public.lesson_right_origin
          )
        )

        and not exists (
          select 1

          from public.lesson_rights existing

          where existing.source_right_id =
                r.id

            and existing.origin =
                'carryover'::public.lesson_right_origin
        )

      order by
        (
          cancellation.first_canceled_at
          is null
        ) asc,

        cancellation.first_canceled_at asc
          nulls last,

        r.sequence_no asc,

        r.id asc

      limit v_carryover_cap

    loop

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
      values (
        v_candidate.student_id,

        v_target_plan.branch_id,

        v_candidate.source_semester_id,

        v_target_plan.semester_id,

        null,

        v_candidate.id,

        'carryover'::public.lesson_right_origin,

        v_candidate.sequence_no,

        v_candidate.duration_minutes,

        'available'::public.lesson_right_status,

        1,

        v_actor_id
      );


      v_carryover_count :=
        v_carryover_count + 1;

    end loop;

  end if;


  -- ==========================================================
  -- 11. EXPIRE ALL REMAINING SOURCE AVAILABLE BASE RIGHTS
  --
  -- Includes source rights that WERE carried.
  --
  -- The carryover row is now the only usable entitlement.
  -- ==========================================================

  update public.lesson_rights r
  set
    status =
      'expired'::public.lesson_right_status,

    expired_at =
      coalesce(
        r.expired_at,
        pg_catalog.now()
      )

  where r.student_id =
        v_source_plan.student_id

    and r.source_semester_id =
        v_source_plan.semester_id

    and r.status =
        'available'::public.lesson_right_status

    and r.origin in (
      'regular_base'::public.lesson_right_origin,
      'flex_base'::public.lesson_right_origin
    );


  get diagnostics
    v_expired_count = row_count;


  -- ==========================================================
  -- 12. COMPLETE SOURCE PLAN
  -- ==========================================================

  update public.student_semester_plans
  set
    status =
      'completed'::public.student_semester_plan_status,

    updated_by =
      v_actor_id

  where id =
        v_source_plan.id;


  -- ==========================================================
  -- 13. AUDIT
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
    v_source_plan.student_id,

    v_source_plan.branch_id,

    v_source_plan.semester_id,

    'STUDENT_SEMESTER_RIGHTS_FINALIZED',

    v_boundary_date,

    v_actor_id,

    jsonb_build_object(
      'sourcePlanId',
        v_source_plan.id,

      'sourceSemesterId',
        v_source_plan.semester_id,

      'targetPlanId',
        p_target_plan_id,

      'targetSemesterId',
        case
          when p_target_plan_id is null
            then null
          else v_target_plan.semester_id
        end,

      'studentType',
        v_source_plan.student_type_snapshot,

      'carryoverCap',
        v_carryover_cap,

      'carryoverCreated',
        v_carryover_count,

      'consumedReservedRights',
        v_consumed_count,

      'expiredAvailableRights',
        v_expired_count
    )
  );


  -- ==========================================================
  -- 14. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'sourcePlanId',
      v_source_plan.id,

    'targetPlanId',
      p_target_plan_id,

    'studentType',
      v_source_plan.student_type_snapshot,

    'carryoverCap',
      v_carryover_cap,

    'carryoverCreated',
      v_carryover_count,

    'consumedReservedRights',
      v_consumed_count,

    'expiredAvailableRights',
      v_expired_count,

    'status',
      'completed'
  );

end;
$$;


revoke all
on function public.finalize_student_semester_rights(
  uuid,
  uuid
)
from public, anon;


grant execute
on function public.finalize_student_semester_rights(
  uuid,
  uuid
)
to authenticated;


comment on function public.finalize_student_semester_rights(
  uuid,
  uuid
) is
  'Atomically finalizes one active student semester plan: consumes finished reserved base rights, materializes capped one-generation carryovers into the immediately following same-branch plan, expires remaining available source base rights, and marks the source plan completed.';