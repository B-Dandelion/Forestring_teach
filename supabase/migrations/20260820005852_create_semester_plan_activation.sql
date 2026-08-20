-- ============================================================
-- Forestring v3
-- Semester plan activation + lesson materialization
--
-- Meaning of ACTIVE:
--   the plan is finalized/materialized.
--
-- It does NOT automatically change students.student_type.
-- Semester-boundary application of current student state is
-- handled separately.
-- ============================================================


-- ============================================================
-- 1. REGULAR SERIES TECHNICAL DURATION RULE
--
-- Historical/test rows are left unvalidated.
-- New/updated series must follow the 15-minute technical grid.
-- ============================================================

alter table public.lesson_series
add constraint lesson_series_duration_15_minute_check
check (
  duration_minutes > 0
  and duration_minutes <= 720
  and mod(duration_minutes, 15) = 0
)
not valid;


-- ============================================================
-- 2. ACTIVATE / MATERIALIZE ONE STUDENT SEMESTER PLAN
--
-- regular:
--   each logical regular schedule slot
--   -> exactly 4 candidates
--   -> 4 regular_base rights
--   -> 4 canonical lessons
--
-- flex:
--   -> activate plan
--   -> existing materialize_flex_base_rights()
--
-- Automatic regular materialization is STRICT:
--   - exactly 4 instructional occurrences per slot
--   - inside teacher work hours
--   - not inside blocked periods
--   - not on ordinary closures
--   - actual teacher/student overlap forbidden
--
-- Existing actual lessons are never silently changed.
-- ============================================================

create or replace function public.activate_student_semester_plan(
  p_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_plan public.student_semester_plans%rowtype;

  v_student_branch_id uuid;
  v_student_profile_active boolean;
  v_student_status public.student_status;

  v_semester_start date;
  v_semester_end date;

  v_has_four_teaching_weeks boolean;

  v_slot record;
  v_candidate record;

  v_slot_count integer := 0;
  v_candidate_count integer := 0;

  v_expected_right_count integer := 0;
  v_existing_right_count integer := 0;
  v_existing_lesson_count integer := 0;

  v_created_right_count integer := 0;
  v_created_lesson_count integer := 0;

  v_right_id uuid;

  v_flex_result jsonb;

  v_plan_was_activated boolean := false;
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


  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';

  end if;


  -- ==========================================================
  -- PLAN
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


  if v_plan.status =
     'completed'::public.student_semester_plan_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_COMPLETED_PLAN_IMMUTABLE';

  end if;


  -- ==========================================================
  -- MANAGER BRANCH
  -- ==========================================================

  if v_actor_role =
       'manager'::public.user_role
     and not private.manager_has_branch(
       v_plan.branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- CURRENT STUDENT VALIDATION
  --
  -- Future branch transfer plans cannot be activated before
  -- the explicit branch-transfer operation is applied.
  -- ==========================================================

  select
    p.branch_id,
    p.is_active,
    s.status
  into
    v_student_branch_id,
    v_student_profile_active,
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


  if not v_student_profile_active
     or v_student_status <>
        'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';

  end if;


  if v_student_branch_id is distinct from
     v_plan.branch_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PLAN_BRANCH_MISMATCH';

  end if;


  -- ==========================================================
  -- EFFECTIVE CALENDAR
  -- ==========================================================

  select
    e.starts_on,
    e.ends_on
  into
    v_semester_start,
    v_semester_end
  from private.get_effective_semester_bounds(
    v_plan.branch_id,
    v_plan.semester_id
  ) e;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND';
  end if;


  select s.has_four_teaching_weeks
  into v_has_four_teaching_weeks
  from private.get_semester_week_summary(
    v_plan.branch_id,
    v_plan.semester_id
  ) s;


  if not coalesce(
    v_has_four_teaching_weeks,
    false
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS';

  end if;


  -- ==========================================================
  -- FLEX
  -- ==========================================================

  if v_plan.student_type_snapshot =
     'flex'::public.student_type then

    if v_plan.flex_base_right_count is null
       or v_plan.flex_duration_minutes is null then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';

    end if;


    if v_plan.status =
       'planned'::public.student_semester_plan_status then

      update public.student_semester_plans
      set
        status =
          'active'::public.student_semester_plan_status,

        updated_by =
          v_actor_id

      where id = v_plan.id;


      v_plan_was_activated := true;

    end if;


    v_flex_result :=
      public.materialize_flex_base_rights(
        v_plan.id
      );


    if v_plan_was_activated then

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
        v_plan.student_id,
        v_plan.branch_id,
        v_plan.semester_id,
        'SEMESTER_PLAN_ACTIVATED',
        v_semester_start,
        v_actor_id,

        jsonb_build_object(
          'planId',
            v_plan.id,

          'studentType',
            'flex',

          'baseRightCount',
            v_plan.flex_base_right_count,

          'durationMinutes',
            v_plan.flex_duration_minutes
        )
      );

    end if;


    return jsonb_build_object(
      'planId',
        v_plan.id,

      'studentId',
        v_plan.student_id,

      'studentType',
        'flex',

      'changed',
        v_plan_was_activated,

      'materialization',
        v_flex_result
    );

  end if;


  -- ==========================================================
  -- REGULAR PLAN
  -- ==========================================================

  if v_plan.student_type_snapshot <>
     'regular'::public.student_type then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_UNKNOWN_STUDENT_TYPE';

  end if;


  -- ==========================================================
  -- ACTIVE LOGICAL SLOTS FOR THIS SEMESTER
  --
  -- A slot overlapping the semester participates.
  --
  -- If a mid-semester slot configuration cannot produce
  -- exactly four occurrences, materialization fails later.
  -- ==========================================================

  select count(*)::integer
  into v_slot_count
  from public.regular_schedule_slots rs
  where rs.student_id =
        v_plan.student_id

    and rs.branch_id =
        v_plan.branch_id

    and rs.starts_on <=
        v_semester_end

    and (
      rs.ends_on is null
      or rs.ends_on >=
         v_semester_start
    );


  if v_slot_count = 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_PLAN_REQUIRES_SCHEDULE_SLOT';

  end if;


  v_expected_right_count :=
    v_slot_count * 4;


  -- ==========================================================
  -- IDEMPOTENT ACTIVE PLAN
  --
  -- Once a regular plan is active, this function does not
  -- reinterpret or rewrite already-materialized lessons.
  --
  -- Dedicated reconciliation RPCs handle later schedule changes.
  -- ==========================================================

  if v_plan.status =
     'active'::public.student_semester_plan_status then

    select count(*)::integer
    into v_existing_right_count
    from public.lesson_rights r
    where r.student_id =
          v_plan.student_id

      and r.source_semester_id =
          v_plan.semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin;


    select count(*)::integer
    into v_existing_lesson_count
    from public.lesson_rights r
    join public.lessons l
      on l.lesson_right_id = r.id
    where r.student_id =
          v_plan.student_id

      and r.source_semester_id =
          v_plan.semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin;


    if v_existing_right_count <>
         v_expected_right_count
       or
       v_existing_lesson_count <>
         v_expected_right_count then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_ACTIVE_PLAN_MATERIALIZATION_INCOMPLETE';

    end if;


    return jsonb_build_object(
      'planId',
        v_plan.id,

      'studentId',
        v_plan.student_id,

      'studentType',
        'regular',

      'changed',
        false,

      'slotCount',
        v_slot_count,

      'rightCount',
        v_existing_right_count,

      'lessonCount',
        v_existing_lesson_count
    );

  end if;


  -- ==========================================================
  -- PLANNED REGULAR PLAN MUST START CLEAN
  -- ==========================================================

  if exists (
    select 1
    from public.lesson_rights r
    where r.student_id =
          v_plan.student_id

      and r.source_semester_id =
          v_plan.semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_PLANNED_REGULAR_PLAN_ALREADY_HAS_RIGHTS';

  end if;


  -- ==========================================================
  -- MATERIALIZE EACH LOGICAL SLOT
  -- ==========================================================

  for v_slot in

    select
      rs.id,
      rs.student_id,
      rs.branch_id,
      rs.starts_on,
      rs.ends_on

    from public.regular_schedule_slots rs

    where rs.student_id =
          v_plan.student_id

      and rs.branch_id =
          v_plan.branch_id

      and rs.starts_on <=
          v_semester_end

      and (
        rs.ends_on is null
        or rs.ends_on >=
           v_semester_start
      )

    order by
      rs.starts_on,
      rs.id

  loop

    -- ========================================================
    -- EXACTLY FOUR THEORETICAL OCCURRENCES
    --
    -- Generate every calendar date in effective semester.
    --
    -- Remove official instructional breaks.
    --
    -- Join whichever series VERSION applies on that date.
    --
    -- This automatically supports:
    --
    -- v1 Tue 18:00 until Sep 14
    -- v2 Thu 19:00 from Sep 15
    --
    -- while preserving one logical schedule slot.
    -- ========================================================

    select count(*)::integer
    into v_candidate_count

    from (
      with teaching_dates as (
        select
          d::date as lesson_date

        from generate_series(
          v_semester_start::timestamp,
          v_semester_end::timestamp,
          interval '1 day'
        ) d

        where not exists (
          select 1
          from public.closure_periods cp

          where cp.branch_id =
                v_plan.branch_id

            and cp.semester_id =
                v_plan.semester_id

            and cp.closure_kind =
                'instructional_break'
                  ::public.closure_kind

            and d::date between
                cp.starts_on
                and cp.ends_on
        )
      )

      select
        td.lesson_date,
        ls.id as series_id

      from teaching_dates td

      join public.lesson_series ls
        on ls.schedule_slot_id =
           v_slot.id

       and ls.student_id =
           v_plan.student_id

       and ls.branch_id =
           v_plan.branch_id

       and td.lesson_date >=
           ls.effective_from

       and (
         ls.effective_until is null
         or td.lesson_date <=
            ls.effective_until
       )

       and extract(
             isodow
             from td.lesson_date
           )::integer =
           ls.weekday

      where td.lesson_date >=
            v_slot.starts_on

        and (
          v_slot.ends_on is null
          or td.lesson_date <=
             v_slot.ends_on
        )
    ) candidate_rows;


    if v_candidate_count <> 4 then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES',
        detail =
          'schedule_slot_id=' ||
          v_slot.id::text ||
          ', candidate_count=' ||
          v_candidate_count::text;

    end if;


    -- ========================================================
    -- BUILD RIGHTS + LESSONS
    -- ========================================================

    for v_candidate in

      with teaching_dates as (
        select
          d::date as lesson_date

        from generate_series(
          v_semester_start::timestamp,
          v_semester_end::timestamp,
          interval '1 day'
        ) d

        where not exists (
          select 1
          from public.closure_periods cp

          where cp.branch_id =
                v_plan.branch_id

            and cp.semester_id =
                v_plan.semester_id

            and cp.closure_kind =
                'instructional_break'
                  ::public.closure_kind

            and d::date between
                cp.starts_on
                and cp.ends_on
        )
      ),

      raw_candidates as (
        select
          td.lesson_date,

          ls.id as series_id,
          ls.teacher_id,
          ls.weekday,
          ls.start_time,
          ls.duration_minutes,

          (
            td.lesson_date
            + ls.start_time
          )
          at time zone 'Asia/Seoul'
            as starts_at

        from teaching_dates td

        join public.lesson_series ls
          on ls.schedule_slot_id =
             v_slot.id

         and ls.student_id =
             v_plan.student_id

         and ls.branch_id =
             v_plan.branch_id

         and td.lesson_date >=
             ls.effective_from

         and (
           ls.effective_until is null
           or td.lesson_date <=
              ls.effective_until
         )

         and extract(
               isodow
               from td.lesson_date
             )::integer =
             ls.weekday

        where td.lesson_date >=
              v_slot.starts_on

          and (
            v_slot.ends_on is null
            or td.lesson_date <=
               v_slot.ends_on
          )
      )

      select
        row_number()
        over (
          order by
            rc.starts_at,
            rc.series_id
        )::integer
          as sequence_no,

        rc.lesson_date,
        rc.series_id,
        rc.teacher_id,
        rc.weekday,
        rc.start_time,
        rc.duration_minutes,
        rc.starts_at,

        rc.starts_at
        +
        pg_catalog.make_interval(
          mins => rc.duration_minutes
        )
          as ends_at

      from raw_candidates rc

      order by
        rc.starts_at,
        rc.series_id

    loop

      -- ======================================================
      -- TECHNICAL DURATION
      -- ======================================================

      if v_candidate.duration_minutes <= 0
         or
         mod(
           v_candidate.duration_minutes,
           15
         ) <> 0 then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SERIES_INVALID_DURATION';

      end if;


      -- ======================================================
      -- ORDINARY CLOSURE
      --
      -- Instructional breaks define the removed teaching week.
      --
      -- An ordinary closure does not silently delete one of
      -- the four contractual lessons.
      --
      -- Therefore configuration must be explicitly resolved.
      -- ======================================================

      if exists (
        select 1
        from public.closure_periods cp

        where cp.branch_id =
              v_plan.branch_id

          and cp.semester_id =
              v_plan.semester_id

          and cp.closure_kind =
              'ordinary'::public.closure_kind

          and v_candidate.lesson_date
              between
              cp.starts_on
              and cp.ends_on
      ) then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE';

      end if;


      -- ======================================================
      -- STRICT WORK HOURS
      -- ======================================================

      if not exists (
        select 1
        from public.teacher_work_hours wh

        where wh.teacher_id =
              v_candidate.teacher_id

          and wh.weekday =
              v_candidate.weekday

          and wh.start_time <=
              v_candidate.start_time

          and wh.end_time >=
              (
                v_candidate.ends_at
                at time zone 'Asia/Seoul'
              )::time
      ) then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',
          detail =
            'schedule_slot_id=' ||
            v_slot.id::text ||
            ', date=' ||
            v_candidate.lesson_date::text;

      end if;


      -- ======================================================
      -- STRICT BLOCKED PERIOD
      -- ======================================================

      if exists (
        select 1
        from public.blocked_periods bp

        where bp.teacher_id =
              v_candidate.teacher_id

          and tstzrange(
                bp.starts_at,
                bp.ends_at,
                '[)'
              )
              &&
              tstzrange(
                v_candidate.starts_at,
                v_candidate.ends_at,
                '[)'
              )
      ) then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_OCCURRENCE_BLOCKED',
          detail =
            'schedule_slot_id=' ||
            v_slot.id::text ||
            ', date=' ||
            v_candidate.lesson_date::text;

      end if;


      -- ======================================================
      -- CREATE RESERVED ENTITLEMENT
      --
      -- A generated regular lesson already occupies the right,
      -- therefore status starts as RESERVED.
      -- ======================================================

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
        created_by,
        reserved_at
      )
      values (
        v_plan.student_id,
        v_plan.branch_id,
        v_plan.semester_id,
        v_plan.semester_id,
        v_slot.id,
        null,
        'regular_base'::public.lesson_right_origin,
        v_candidate.sequence_no,
        v_candidate.duration_minutes,
        'reserved'::public.lesson_right_status,
        0,
        v_actor_id,
        now()
      )
      returning id
      into v_right_id;


      v_created_right_count :=
        v_created_right_count + 1;


      -- ======================================================
      -- CREATE CANONICAL ACTUAL LESSON
      --
      -- occurrence_at = original generated occurrence identity.
      --
      -- Future one-off move:
      --   starts_at changes
      --   occurrence_at stays.
      -- ======================================================

      begin

        insert into public.lessons (
          series_id,
          student_id,
          teacher_id,
          occurrence_at,
          starts_at,
          duration_minutes,
          lesson_type,
          status,
          lesson_right_id
        )
        values (
          v_candidate.series_id,
          v_plan.student_id,
          v_candidate.teacher_id,
          v_candidate.starts_at,
          v_candidate.starts_at,
          v_candidate.duration_minutes,
          'regular'::public.lesson_type,
          'scheduled'::public.lesson_status,
          v_right_id
        );


      exception
        when exclusion_violation then

          raise exception using
            errcode = 'P0001',
            message =
              'FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT',
            detail =
              'schedule_slot_id=' ||
              v_slot.id::text ||
              ', starts_at=' ||
              v_candidate.starts_at::text;

      end;


      v_created_lesson_count :=
        v_created_lesson_count + 1;

    end loop;

  end loop;


  -- ==========================================================
  -- FINAL EXACT COUNTS
  -- ==========================================================

  if v_created_right_count <>
       v_expected_right_count
     or
     v_created_lesson_count <>
       v_expected_right_count then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_MATERIALIZATION_COUNT_MISMATCH';

  end if;


  -- ==========================================================
  -- ACTIVATE PLAN
  -- ==========================================================

  update public.student_semester_plans
  set
    status =
      'active'::public.student_semester_plan_status,

    updated_by =
      v_actor_id

  where id =
        v_plan.id;


  -- ==========================================================
  -- AUDIT
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
    v_plan.student_id,
    v_plan.branch_id,
    v_plan.semester_id,
    'SEMESTER_PLAN_ACTIVATED',
    v_semester_start,
    v_actor_id,

    jsonb_build_object(
      'planId',
        v_plan.id,

      'studentType',
        'regular',

      'slotCount',
        v_slot_count,

      'rightCount',
        v_created_right_count,

      'lessonCount',
        v_created_lesson_count
    )
  );


  return jsonb_build_object(
    'planId',
      v_plan.id,

    'studentId',
      v_plan.student_id,

    'studentType',
      'regular',

    'changed',
      true,

    'slotCount',
      v_slot_count,

    'rightCount',
      v_created_right_count,

    'lessonCount',
      v_created_lesson_count
  );

end;
$$;


-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on function public.activate_student_semester_plan(uuid)
from public, anon;


grant execute
on function public.activate_student_semester_plan(uuid)
to authenticated;


comment on function public.activate_student_semester_plan(uuid) is
  'Finalizes/materializes one student semester plan. Regular plans create exactly four rights and canonical lessons per logical schedule slot; flex plans materialize configured flex rights. Does not change current students.student_type.';