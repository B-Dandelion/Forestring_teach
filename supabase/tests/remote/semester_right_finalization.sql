begin;

do $$
declare
  -- ==========================================================
  -- ACTORS / FIXTURE
  -- ==========================================================

  v_manager_id uuid;
  v_other_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;

  v_regular_student_id uuid;
  v_flex_student_id uuid;

  -- ==========================================================
  -- SEMESTERS
  --
  -- Past dates are intentional because finalization refuses
  -- to run before the source semester is actually over.
  -- ==========================================================

  v_source_semester_id uuid;
  v_target_semester_id uuid;
  v_later_semester_id uuid;

  -- ==========================================================
  -- PLANS
  -- ==========================================================

  v_regular_source_plan_id uuid;
  v_regular_target_plan_id uuid;
  v_regular_later_plan_id uuid;

  v_flex_source_plan_id uuid;
  v_flex_target_plan_id uuid;

  -- ==========================================================
  -- REGULAR
  -- ==========================================================

  v_regular_slot_id uuid;
  v_regular_series_id uuid;

  v_regular_right_1 uuid;
  v_regular_right_2 uuid;
  v_regular_right_3 uuid;
  v_regular_right_4 uuid;

  v_regular_lesson_1 uuid;
  v_regular_lesson_2 uuid;
  v_regular_lesson_3 uuid;
  v_regular_lesson_4 uuid;

  -- ==========================================================
  -- FLEX
  -- ==========================================================

  v_flex_right_1 uuid;
  v_flex_right_2 uuid;
  v_flex_right_3 uuid;
  v_flex_right_4 uuid;
  v_flex_right_5 uuid;
  v_flex_right_6 uuid;
  v_flex_right_7 uuid;
  v_flex_right_8 uuid;

  v_flex_lesson_4 uuid;
  v_flex_lesson_6 uuid;
  v_flex_lesson_8 uuid;

  -- ==========================================================
  -- GENERAL
  -- ==========================================================

  v_result jsonb;

  v_count integer;
  v_denied boolean;

begin

  -- ==========================================================
  -- 1. PRIMARY FIXTURE
  --
  -- Need:
  --   same-branch manager
  --   normal teacher
  --   active student
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    teacher_profile.id,
    student_profile.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id,
    v_regular_student_id

  from public.profiles manager_profile

  join public.teachers manager_teacher
    on manager_teacher.id =
       manager_profile.id

  join public.profiles teacher_profile
    on teacher_profile.branch_id =
       manager_profile.branch_id

   and teacher_profile.role =
       'teacher'::public.user_role

   and teacher_profile.is_active = true

  join public.teachers teacher_entity
    on teacher_entity.id =
       teacher_profile.id

  join public.profiles student_profile
    on student_profile.branch_id =
       manager_profile.branch_id

   and student_profile.role =
       'student'::public.user_role

   and student_profile.is_active = true

  join public.students student_entity
    on student_entity.id =
       student_profile.id

   and student_entity.status =
       'active'::public.student_status

  where manager_profile.role =
        'manager'::public.user_role

    and manager_profile.is_active = true

    and manager_profile.branch_id is not null

  order by
    manager_profile.created_at,
    teacher_profile.created_at,
    student_profile.created_at

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + active student';
  end if;


  -- ==========================================================
  -- 2. SECOND STUDENT FOR FLEX TEST
  --
  -- Keep regular and flex tests independent.
  --
  -- We only borrow another existing students row and normalize
  -- its branch/activity inside this transaction.
  -- ROLLBACK restores everything.
  -- ==========================================================

  select p.id
  into v_flex_student_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id <>
        v_regular_student_id

  order by
    case
      when p.branch_id = v_branch_id
        then 0
      else 1
    end,
    p.created_at

  limit 1;


  if v_flex_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second student entity';
  end if;


  update public.profiles
  set
    branch_id = v_branch_id,
    is_active = true
  where id =
        v_flex_student_id;


  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_flex_student_id;


  -- ==========================================================
  -- 3. OTHER-BRANCH MANAGER
  --
  -- Used for branch permission rejection.
  -- ==========================================================

  select p.id
  into v_other_manager_id

  from public.profiles p

  where p.role =
        'manager'::public.user_role

    and p.is_active = true

    and p.branch_id is not null

    and p.branch_id <>
        v_branch_id

  order by p.created_at

  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 4. THREE NON-OVERLAPPING 28-DAY SEMESTERS
  --
  -- source:
  --   2000-01-03 ~ 2000-01-30
  --
  -- target:
  --   2000-01-31 ~ 2000-02-27
  --
  -- later:
  --   2000-02-28 ~ 2000-03-26
  --
  -- "later" is valid globally, but NOT consecutive to source.
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FINALIZE-SOURCE-2000',
    date '2000-01-03',
    date '2000-01-30'
  )
  returning id
  into v_source_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FINALIZE-TARGET-2000',
    date '2000-01-31',
    date '2000-02-27'
  )
  returning id
  into v_target_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-FINALIZE-LATER-2000',
    date '2000-02-28',
    date '2000-03-26'
  )
  returning id
  into v_later_semester_id;


  -- ==========================================================
  -- 5. REGULAR SOURCE/TARGET/LATER PLANS
  -- ==========================================================

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values (
    v_regular_student_id,
    v_source_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_regular_source_plan_id;


  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values (
    v_regular_student_id,
    v_target_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_regular_target_plan_id;


  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values (
    v_regular_student_id,
    v_later_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_regular_later_plan_id;


  -- ==========================================================
  -- 6. FLEX SOURCE/TARGET PLANS
  --
  -- N = 8
  -- carryover cap = floor(8 / 4) = 2
  -- ==========================================================

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status,
    created_by,
    updated_by
  )
  values (
    v_flex_student_id,
    v_source_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    8,
    30,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_flex_source_plan_id;


  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    flex_base_right_count,
    flex_duration_minutes,
    status,
    created_by,
    updated_by
  )
  values (
    v_flex_student_id,
    v_target_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    8,
    30,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_flex_target_plan_id;


  -- ==========================================================
  -- 7. REGULAR SLOT + SERIES
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    ends_on,
    created_by
  )
  values (
    v_regular_student_id,
    v_branch_id,
    date '2000-01-03',
    null,
    v_manager_id
  )
  returning id
  into v_regular_slot_id;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    effective_until,
    schedule_slot_id
  )
  values (
    v_regular_student_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2000-01-03',
    date '2000-01-30',
    v_regular_slot_id
  )
  returning id
  into v_regular_series_id;


  -- ==========================================================
  -- 8. FOUR REGULAR RIGHTS
  --
  -- #1 #2 #3:
  --   canceled in semester
  --   therefore AVAILABLE
  --
  -- #4:
  --   remained scheduled through semester
  --   therefore RESERVED
  --
  -- Expected finalization:
  --   exactly ONE available right carried
  --   all three source available rights expired
  --   #4 consumed
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by
  )
  values
    (
      v_regular_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      1,
      30,
      'available'::public.lesson_right_status,
      v_manager_id
    ),
    (
      v_regular_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      2,
      30,
      'available'::public.lesson_right_status,
      v_manager_id
    ),
    (
      v_regular_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      3,
      30,
      'available'::public.lesson_right_status,
      v_manager_id
    ),
    (
      v_regular_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      v_regular_slot_id,
      'regular_base'::public.lesson_right_origin,
      4,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id
    );


  select id into v_regular_right_1
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 1;


  select id into v_regular_right_2
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 2;


  select id into v_regular_right_3
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 3;


  select id into v_regular_right_4
  from public.lesson_rights
  where schedule_slot_id = v_regular_slot_id
    and source_semester_id = v_source_semester_id
    and sequence_no = 4;


  -- ==========================================================
  -- 9. REGULAR CANONICAL LESSONS
  --
  -- #1 #2 #3 canceled.
  -- #4 scheduled and already in the past.
  -- ==========================================================

  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values
    (
      v_regular_series_id,
      v_regular_student_id,
      v_teacher_id,
      timestamptz '2000-01-03 18:00:00+09',
      timestamptz '2000-01-03 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_regular_right_1,
      v_regular_student_id,
      timestamptz '2000-01-02 12:00:00+09',
      'finalization test'
    ),
    (
      v_regular_series_id,
      v_regular_student_id,
      v_teacher_id,
      timestamptz '2000-01-10 18:00:00+09',
      timestamptz '2000-01-10 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_regular_right_2,
      v_regular_student_id,
      timestamptz '2000-01-09 12:00:00+09',
      'finalization test'
    ),
    (
      v_regular_series_id,
      v_regular_student_id,
      v_teacher_id,
      timestamptz '2000-01-17 18:00:00+09',
      timestamptz '2000-01-17 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_regular_right_3,
      v_regular_student_id,
      timestamptz '2000-01-16 12:00:00+09',
      'finalization test'
    ),
    (
      v_regular_series_id,
      v_regular_student_id,
      v_teacher_id,
      timestamptz '2000-01-24 18:00:00+09',
      timestamptz '2000-01-24 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_regular_right_4,
      null,
      null,
      null
    );


  select id into v_regular_lesson_1
  from public.lessons
  where lesson_right_id = v_regular_right_1;

  select id into v_regular_lesson_2
  from public.lessons
  where lesson_right_id = v_regular_right_2;

  select id into v_regular_lesson_3
  from public.lessons
  where lesson_right_id = v_regular_right_3;

  select id into v_regular_lesson_4
  from public.lessons
  where lesson_right_id = v_regular_right_4;


  -- ==========================================================
  -- 10. REGULAR CANCELLATION HISTORY
  --
  -- All three AVAILABLE regular rights are genuine canceled
  -- entitlements.
  --
  -- #1 is oldest, so it should be the ONE carried right.
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    canceled_at,
    reason
  )
  values
    (
      v_regular_lesson_1,
      v_regular_right_1,
      v_regular_student_id,
      v_branch_id,
      'student'::public.lesson_cancellation_origin,
      v_regular_student_id,
      true,
      timestamptz '2000-01-02 12:00:00+09',
      'regular #1'
    ),
    (
      v_regular_lesson_2,
      v_regular_right_2,
      v_regular_student_id,
      v_branch_id,
      'student'::public.lesson_cancellation_origin,
      v_regular_student_id,
      true,
      timestamptz '2000-01-09 12:00:00+09',
      'regular #2'
    ),
    (
      v_regular_lesson_3,
      v_regular_right_3,
      v_regular_student_id,
      v_branch_id,
      'academy'::public.lesson_cancellation_origin,
      v_manager_id,
      false,
      timestamptz '2000-01-16 12:00:00+09',
      'regular academy cancellation'
    );


  -- ==========================================================
  -- 11. FLEX 8 BASE RIGHTS
  --
  -- Expected state before finalization:
  --
  -- #1 available, never booked
  -- #2 available, never booked
  -- #3 consumed
  -- #4 available, canceled
  -- #5 consumed
  -- #6 available, canceled
  -- #7 consumed
  -- #8 reserved + past scheduled lesson
  --
  -- Carryover cap = 2.
  --
  -- Priority rule should select #4 and #6 because cancellation
  -- history beats never-booked #1/#2.
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    consumed_at,
    created_by
  )
  values
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      1,
      30,
      'available'::public.lesson_right_status,
      null,
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      2,
      30,
      'available'::public.lesson_right_status,
      null,
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      3,
      30,
      'consumed'::public.lesson_right_status,
      timestamptz '2000-01-08 12:00:00+09',
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      4,
      30,
      'available'::public.lesson_right_status,
      null,
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      5,
      30,
      'consumed'::public.lesson_right_status,
      timestamptz '2000-01-12 12:00:00+09',
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      6,
      30,
      'available'::public.lesson_right_status,
      null,
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      7,
      30,
      'consumed'::public.lesson_right_status,
      timestamptz '2000-01-19 12:00:00+09',
      v_manager_id
    ),
    (
      v_flex_student_id,
      v_branch_id,
      v_source_semester_id,
      v_source_semester_id,
      'flex_base'::public.lesson_right_origin,
      8,
      30,
      'reserved'::public.lesson_right_status,
      null,
      v_manager_id
    );


  select id into v_flex_right_1
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 1;

  select id into v_flex_right_2
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 2;

  select id into v_flex_right_3
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 3;

  select id into v_flex_right_4
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 4;

  select id into v_flex_right_5
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 5;

  select id into v_flex_right_6
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 6;

  select id into v_flex_right_7
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 7;

  select id into v_flex_right_8
  from public.lesson_rights
  where student_id = v_flex_student_id
    and source_semester_id = v_source_semester_id
    and origin = 'flex_base'::public.lesson_right_origin
    and sequence_no = 8;


  -- ==========================================================
  -- 12. FLEX CANCELED / RESERVED LESSONS
  -- ==========================================================

  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values
    (
      v_flex_student_id,
      v_teacher_id,
      timestamptz '2000-01-12 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_flex_right_4,
      v_flex_student_id,
      timestamptz '2000-01-11 10:00:00+09',
      'flex canceled #4'
    ),
    (
      v_flex_student_id,
      v_teacher_id,
      timestamptz '2000-01-19 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_flex_right_6,
      v_flex_student_id,
      timestamptz '2000-01-18 10:00:00+09',
      'flex canceled #6'
    ),
    (
      v_flex_student_id,
      v_teacher_id,
      timestamptz '2000-01-26 10:00:00+09',
      30,
      'flex'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_flex_right_8,
      null,
      null,
      null
    );


  select id into v_flex_lesson_4
  from public.lessons
  where lesson_right_id = v_flex_right_4;

  select id into v_flex_lesson_6
  from public.lessons
  where lesson_right_id = v_flex_right_6;

  select id into v_flex_lesson_8
  from public.lessons
  where lesson_right_id = v_flex_right_8;


  -- ==========================================================
  -- 13. FLEX CANCELLATION HISTORY
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    canceled_at,
    reason
  )
  values
    (
      v_flex_lesson_4,
      v_flex_right_4,
      v_flex_student_id,
      v_branch_id,
      'student'::public.lesson_cancellation_origin,
      v_flex_student_id,
      true,
      timestamptz '2000-01-11 10:00:00+09',
      'flex #4'
    ),
    (
      v_flex_lesson_6,
      v_flex_right_6,
      v_flex_student_id,
      v_branch_id,
      'student'::public.lesson_cancellation_origin,
      v_flex_student_id,
      true,
      timestamptz '2000-01-18 10:00:00+09',
      'flex #6'
    );


  -- ==========================================================
  -- 14. STUDENT MAY NOT FINALIZE
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_regular_student_id::text,
    true
  );

  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_regular_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.finalize_student_semester_rights(
      v_regular_source_plan_id,
      v_regular_target_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_SEMESTER_FINALIZATION_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: student finalized semester rights';
  end if;


  -- ==========================================================
  -- 15. CROSS-BRANCH MANAGER MAY NOT FINALIZE
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_other_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_other_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.finalize_student_semester_rights(
      v_regular_source_plan_id,
      v_regular_target_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: cross-branch manager finalized plan';
  end if;


  -- ==========================================================
  -- 16. NON-CONSECUTIVE TARGET MUST FAIL
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.finalize_student_semester_rights(
      v_regular_source_plan_id,
      v_regular_later_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_TARGET_SEMESTER_NOT_CONSECUTIVE' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: non-consecutive target semester accepted';
  end if;


  -- Source must still be untouched after rejected attempts.
  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.id = v_regular_source_plan_id
      and sp.status =
          'active'::public.student_semester_plan_status
  ) then
    raise exception
      'TEST_FAILED: rejected finalization mutated source plan';
  end if;


  -- ==========================================================
  -- 17. FINALIZE REGULAR
  -- ==========================================================

  v_result :=
    public.finalize_student_semester_rights(
      v_regular_source_plan_id,
      v_regular_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> true
     or
     (v_result ->> 'carryoverCap')::integer <> 1
     or
     (v_result ->> 'carryoverCreated')::integer <> 1
     or
     (v_result ->> 'consumedReservedRights')::integer <> 1
     or
     (v_result ->> 'expiredAvailableRights')::integer <> 3 then

    raise exception
      'TEST_FAILED: regular finalization result incorrect: %',
      v_result;
  end if;


  -- ==========================================================
  -- 18. REGULAR: EXACTLY ONE CARRYOVER
  --
  -- Oldest cancellation = right #1.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_regular_student_id

    and r.origin =
        'carryover'::public.lesson_right_origin

    and r.usable_semester_id =
        v_target_semester_id;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: regular expected exactly 1 carryover, got %',
      v_count;
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.student_id =
          v_regular_student_id

      and r.origin =
          'carryover'::public.lesson_right_origin

      and r.source_right_id =
          v_regular_right_1

      and r.source_semester_id =
          v_source_semester_id

      and r.usable_semester_id =
          v_target_semester_id

      and r.sequence_no = 1

      and r.duration_minutes = 30

      and r.schedule_slot_id is null

      and r.carryover_count = 1

      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: regular carryover provenance incorrect';
  end if;


  -- ==========================================================
  -- 19. REGULAR SOURCE AVAILABLE RIGHTS ALL EXPIRED
  --
  -- Including the source right that was carried.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_regular_right_1,
    v_regular_right_2,
    v_regular_right_3
  )

    and r.status =
        'expired'::public.lesson_right_status

    and r.expired_at is not null;


  if v_count <> 3 then
    raise exception
      'TEST_FAILED: regular source available rights not all expired';
  end if;


  -- Reserved #4 becomes consumed.
  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_regular_right_4

      and r.status =
          'consumed'::public.lesson_right_status

      and r.consumed_at is not null
  ) then
    raise exception
      'TEST_FAILED: regular reserved right was not consumed';
  end if;


  -- ==========================================================
  -- 20. REGULAR SOURCE PLAN COMPLETED / TARGET UNCHANGED
  -- ==========================================================

  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.id =
          v_regular_source_plan_id
      and sp.status =
          'completed'::public.student_semester_plan_status
  ) then
    raise exception
      'TEST_FAILED: regular source plan not completed';
  end if;


  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.id =
          v_regular_target_plan_id
      and sp.status =
          'planned'::public.student_semester_plan_status
  ) then
    raise exception
      'TEST_FAILED: finalization unexpectedly changed target plan';
  end if;


  -- ==========================================================
  -- 21. REGULAR IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.finalize_student_semester_rights(
      v_regular_source_plan_id,
      v_regular_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> false
     or
     (v_result ->> 'carryoverCreated')::integer <> 1 then

    raise exception
      'TEST_FAILED: regular idempotency result incorrect: %',
      v_result;
  end if;


  select count(*)::integer
  into v_count
  from public.lesson_rights r
  where r.student_id =
        v_regular_student_id
    and r.origin =
        'carryover'::public.lesson_right_origin
    and r.usable_semester_id =
        v_target_semester_id;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: regular idempotent call duplicated carryover';
  end if;


  -- ==========================================================
  -- 22. FINALIZE FLEX
  -- ==========================================================

  v_result :=
    public.finalize_student_semester_rights(
      v_flex_source_plan_id,
      v_flex_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> true
     or
     (v_result ->> 'carryoverCap')::integer <> 2
     or
     (v_result ->> 'carryoverCreated')::integer <> 2
     or
     (v_result ->> 'consumedReservedRights')::integer <> 1
     or
     (v_result ->> 'expiredAvailableRights')::integer <> 4 then

    raise exception
      'TEST_FAILED: flex finalization result incorrect: %',
      v_result;
  end if;


  -- ==========================================================
  -- 23. FLEX: EXACTLY TWO CARRYOVERS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_flex_student_id

    and r.origin =
        'carryover'::public.lesson_right_origin

    and r.usable_semester_id =
        v_target_semester_id;


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: flex expected 2 carryovers, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 24. FLEX PRIORITY
  --
  -- Canceled #4 and #6 MUST be carried.
  --
  -- Never-booked #1/#2 must NOT be carried while canceled
  -- entitlements exist and fill the whole cap.
  -- ==========================================================

  if not exists (
    select 1
    from public.lesson_rights r
    where r.origin =
          'carryover'::public.lesson_right_origin
      and r.source_right_id =
          v_flex_right_4
      and r.student_id =
          v_flex_student_id
      and r.source_semester_id =
          v_source_semester_id
      and r.usable_semester_id =
          v_target_semester_id
      and r.sequence_no = 4
      and r.duration_minutes = 30
      and r.carryover_count = 1
      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: canceled flex right #4 was not carried';
  end if;


  if not exists (
    select 1
    from public.lesson_rights r
    where r.origin =
          'carryover'::public.lesson_right_origin
      and r.source_right_id =
          v_flex_right_6
      and r.student_id =
          v_flex_student_id
      and r.source_semester_id =
          v_source_semester_id
      and r.usable_semester_id =
          v_target_semester_id
      and r.sequence_no = 6
      and r.duration_minutes = 30
      and r.carryover_count = 1
      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: canceled flex right #6 was not carried';
  end if;


  if exists (
    select 1
    from public.lesson_rights r
    where r.origin =
          'carryover'::public.lesson_right_origin
      and r.source_right_id in (
        v_flex_right_1,
        v_flex_right_2
      )
  ) then
    raise exception
      'TEST_FAILED: untouched flex right outranked canceled right';
  end if;


  -- ==========================================================
  -- 25. FLEX SOURCE AVAILABLE RIGHTS ALL EXPIRED
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_flex_right_1,
    v_flex_right_2,
    v_flex_right_4,
    v_flex_right_6
  )

    and r.status =
        'expired'::public.lesson_right_status

    and r.expired_at is not null;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: flex source available rights not all expired';
  end if;


  -- Existing consumed rights stay consumed.
  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_flex_right_3,
    v_flex_right_5,
    v_flex_right_7
  )

    and r.status =
        'consumed'::public.lesson_right_status;


  if v_count <> 3 then
    raise exception
      'TEST_FAILED: existing flex consumed rights changed unexpectedly';
  end if;


  -- Reserved #8 becomes consumed.
  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_flex_right_8

      and r.status =
          'consumed'::public.lesson_right_status

      and r.consumed_at is not null
  ) then
    raise exception
      'TEST_FAILED: flex reserved right was not consumed';
  end if;


  -- ==========================================================
  -- 26. FLEX SOURCE PLAN COMPLETED
  -- ==========================================================

  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.id =
          v_flex_source_plan_id
      and sp.status =
          'completed'::public.student_semester_plan_status
  ) then
    raise exception
      'TEST_FAILED: flex source plan not completed';
  end if;


  -- ==========================================================
  -- 27. FLEX IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.finalize_student_semester_rights(
      v_flex_source_plan_id,
      v_flex_target_plan_id
    );


  if (v_result ->> 'changed')::boolean <> false
     or
     (v_result ->> 'carryoverCreated')::integer <> 2 then

    raise exception
      'TEST_FAILED: flex idempotency result incorrect: %',
      v_result;
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_flex_student_id

    and r.origin =
        'carryover'::public.lesson_right_origin

    and r.usable_semester_id =
        v_target_semester_id;


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: flex idempotent call duplicated carryovers';
  end if;


  -- ==========================================================
  -- 28. NO SOURCE BASE RIGHT REMAINS AVAILABLE
  -- ==========================================================

  if exists (
    select 1
    from public.lesson_rights r

    where r.source_semester_id =
          v_source_semester_id

      and r.student_id in (
        v_regular_student_id,
        v_flex_student_id
      )

      and r.origin in (
        'regular_base'::public.lesson_right_origin,
        'flex_base'::public.lesson_right_origin
      )

      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: source-semester base entitlement remained available';
  end if;


  -- ==========================================================
  -- 29. EXACTLY ONE AUDIT PER SUCCESSFUL SOURCE FINALIZATION
  --
  -- Idempotent calls must not add another finalization audit.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_SEMESTER_RIGHTS_FINALIZED'

    and a.semester_id =
        v_source_semester_id

    and a.subject_profile_id in (
      v_regular_student_id,
      v_flex_student_id
    );


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: expected exactly 2 finalization audits, got %',
      v_count;
  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_SEMESTER_RIGHTS_FINALIZED'

      and a.subject_profile_id =
          v_regular_student_id

      and (
        a.details
        ->> 'carryoverCreated'
      )::integer = 1

      and (
        a.details
        ->> 'consumedReservedRights'
      )::integer = 1

      and (
        a.details
        ->> 'expiredAvailableRights'
      )::integer = 3
  ) then
    raise exception
      'TEST_FAILED: regular finalization audit incorrect';
  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_SEMESTER_RIGHTS_FINALIZED'

      and a.subject_profile_id =
          v_flex_student_id

      and (
        a.details
        ->> 'carryoverCreated'
      )::integer = 2

      and (
        a.details
        ->> 'consumedReservedRights'
      )::integer = 1

      and (
        a.details
        ->> 'expiredAvailableRights'
      )::integer = 4
  ) then
    raise exception
      'TEST_FAILED: flex finalization audit incorrect';
  end if;

end;
$$;


select
  'PASS: semester right finalization / regular carryover 1 / flex carryover floor(N/4) / canceled-right priority / provenance / source expiry / reserved consumption / completion / idempotency / consecutive semester / branch auth'
  as test_result;

rollback;
