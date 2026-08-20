begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_other_manager_id uuid;
  v_student_id uuid;

  v_regular_semester_id uuid;
  v_flex_semester_id uuid;
  v_no_hours_semester_id uuid;
  v_blocked_semester_id uuid;

  v_regular_plan_id uuid;
  v_flex_plan_id uuid;
  v_no_hours_plan_id uuid;
  v_blocked_plan_id uuid;

  v_slot_id uuid;
  v_series_id uuid;

  v_result jsonb;

  v_count integer;
  v_audit_count integer;

  v_denied boolean;

  v_original_student_type public.student_type;
begin

  -- ==========================================================
  -- 1. FIXTURE
  --
  -- Use manager as teacher.
  -- Need one active REGULAR student in same branch.
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    student_profile.id,
    student_entity.student_type
  into
    v_manager_id,
    v_branch_id,
    v_student_id,
    v_original_student_type

  from public.profiles manager_profile

  join public.teachers manager_teacher
    on manager_teacher.id =
       manager_profile.id

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

   and student_entity.student_type =
       'regular'::public.student_type

  where manager_profile.role =
        'manager'::public.user_role

    and manager_profile.is_active = true

    and manager_profile.branch_id is not null

    -- Avoid any unlikely historical recurring conflict at
    -- Monday 03:00 for this test pair.
    and not exists (
      select 1
      from public.lesson_series existing_series

      where existing_series.student_id =
            student_profile.id

        and existing_series.weekday = 1

        and int4range(
              (
                extract(
                  hour
                  from existing_series.start_time
                )::integer * 60

                +

                extract(
                  minute
                  from existing_series.start_time
                )::integer
              ),

              (
                extract(
                  hour
                  from existing_series.start_time
                )::integer * 60

                +

                extract(
                  minute
                  from existing_series.start_time
                )::integer

                +

                existing_series.duration_minutes
              ),

              '[)'
            )
            &&
            int4range(
              180,
              210,
              '[)'
            )
    )

  order by
    manager_profile.created_at,
    student_profile.created_at

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + regular student in same branch';
  end if;


  -- ==========================================================
  -- 2. OTHER-BRANCH MANAGER
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
  -- 3. CLEAN TEST TEACHER AVAILABILITY
  --
  -- Everything is rolled back later.
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id = v_manager_id;


  delete from public.blocked_periods
  where teacher_id = v_manager_id;


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_manager_id,
    1,
    time '02:00',
    time '05:00'
  );


  -- ==========================================================
  -- 4. TEST SEMESTERS
  --
  -- REGULAR:
  --   2099-04-06 ~ 2099-05-10 = 5 weeks
  --   minus 1 instructional break = 4 teaching weeks
  --
  -- FLEX:
  --   4 weeks
  --
  -- NO HOURS:
  --   4 weeks
  --
  -- BLOCKED:
  --   4 weeks
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-ACTIVATION-REGULAR-2099',
    date '2099-04-06',
    date '2099-05-10'
  )
  returning id
  into v_regular_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-ACTIVATION-FLEX-2099',
    date '2099-05-11',
    date '2099-06-07'
  )
  returning id
  into v_flex_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-ACTIVATION-NO-HOURS-2099',
    date '2099-06-08',
    date '2099-07-05'
  )
  returning id
  into v_no_hours_semester_id;


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-ACTIVATION-BLOCKED-2099',
    date '2099-07-06',
    date '2099-08-02'
  )
  returning id
  into v_blocked_semester_id;


  -- ==========================================================
  -- 5. ONE-WEEK OFFICIAL BREAK
  --
  -- Removes Monday 2099-04-20.
  --
  -- Remaining Monday occurrences:
  --   04/06
  --   04/13
  --   04/27
  --   05/04
  -- ==========================================================

  insert into public.closure_periods (
    semester_id,
    branch_id,
    starts_on,
    ends_on,
    reason,
    closure_kind
  )
  values (
    v_regular_semester_id,
    v_branch_id,
    date '2099-04-20',
    date '2099-04-26',
    'remote materialization test',
    'instructional_break'::public.closure_kind
  );


  -- ==========================================================
  -- 6. ONE LOGICAL REGULAR SLOT
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2099-04-06',
    v_manager_id
  )
  returning id
  into v_slot_id;


  -- ==========================================================
  -- 7. ONE SERIES VERSION
  --
  -- Monday 03:00 / 30 minutes
  -- Applies through every test semester.
  -- ==========================================================

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
    v_student_id,
    v_manager_id,
    1,
    time '03:00',
    30,
    date '2099-04-06',
    date '2099-08-02',
    v_slot_id
  )
  returning id
  into v_series_id;


  -- ==========================================================
  -- 8. PLANS
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
    v_student_id,
    v_regular_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_regular_plan_id;


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
    v_student_id,
    v_flex_semester_id,
    v_branch_id,
    'flex'::public.student_type,
    8,
    30,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_flex_plan_id;


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
    v_student_id,
    v_no_hours_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_no_hours_plan_id;


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
    v_student_id,
    v_blocked_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'planned'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_blocked_plan_id;


  -- ==========================================================
  -- 9. SAME-BRANCH MANAGER JWT
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
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
      'sub',
        v_manager_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 10. REGULAR ACTIVATION
  -- ==========================================================

  v_result :=
    public.activate_student_semester_plan(
      v_regular_plan_id
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: regular activation should change plan';

  end if;


  if (v_result ->> 'slotCount')::integer <> 1 then
    raise exception
      'TEST_FAILED: expected slotCount=1, got %',
      v_result ->> 'slotCount';
  end if;


  if (v_result ->> 'rightCount')::integer <> 4 then
    raise exception
      'TEST_FAILED: expected rightCount=4, got %',
      v_result ->> 'rightCount';
  end if;


  if (v_result ->> 'lessonCount')::integer <> 4 then
    raise exception
      'TEST_FAILED: expected lessonCount=4, got %',
      v_result ->> 'lessonCount';
  end if;


  -- ==========================================================
  -- 11. REGULAR PLAN ACTIVE
  -- ==========================================================

  if not exists (
    select 1
    from public.student_semester_plans sp

    where sp.id =
          v_regular_plan_id

      and sp.status =
          'active'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: regular plan did not become active';

  end if;


  -- ==========================================================
  -- 12. EXACTLY FOUR REGULAR RIGHTS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_regular_semester_id

    and r.usable_semester_id =
        v_regular_semester_id

    and r.schedule_slot_id =
        v_slot_id

    and r.origin =
        'regular_base'::public.lesson_right_origin

    and r.status =
        'reserved'::public.lesson_right_status

    and r.duration_minutes = 30;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: expected exactly 4 reserved regular rights, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 13. EXACT NUMBERING #1 ~ #4
  -- ==========================================================

  if (
    select array_agg(
      r.sequence_no
      order by r.sequence_no
    )

    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.source_semester_id =
          v_regular_semester_id

      and r.schedule_slot_id =
          v_slot_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) <> array[1, 2, 3, 4] then

    raise exception
      'TEST_FAILED: regular entitlement numbering is not 1..4';

  end if;


  -- ==========================================================
  -- 14. EXACTLY FOUR CANONICAL LESSONS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  join public.lessons l
    on l.lesson_right_id =
       r.id

  where r.source_semester_id =
        v_regular_semester_id

    and r.student_id =
        v_student_id

    and r.origin =
        'regular_base'::public.lesson_right_origin

    and l.series_id =
        v_series_id

    and l.teacher_id =
        v_manager_id

    and l.student_id =
        v_student_id

    and l.lesson_type =
        'regular'::public.lesson_type

    and l.status =
        'scheduled'::public.lesson_status;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: expected exactly 4 canonical regular lessons, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 15. CORRECT DATES
  --
  -- Closure week Monday 04/20 MUST NOT exist.
  -- ==========================================================

  if (
    select array_agg(
      (
        l.starts_at
        at time zone 'Asia/Seoul'
      )::date
      order by l.starts_at
    )

    from public.lesson_rights r

    join public.lessons l
      on l.lesson_right_id =
         r.id

    where r.source_semester_id =
          v_regular_semester_id

      and r.student_id =
          v_student_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) <> array[
    date '2099-04-06',
    date '2099-04-13',
    date '2099-04-27',
    date '2099-05-04'
  ] then

    raise exception
      'TEST_FAILED: instructional-break occurrence calculation is wrong';

  end if;


  -- ==========================================================
  -- 16. INITIAL OCCURRENCE IDENTITY
  -- ==========================================================

  if exists (
    select 1

    from public.lesson_rights r

    join public.lessons l
      on l.lesson_right_id =
         r.id

    where r.source_semester_id =
          v_regular_semester_id

      and r.student_id =
          v_student_id

      and r.origin =
          'regular_base'::public.lesson_right_origin

      and l.occurrence_at is distinct from
          l.starts_at
  ) then

    raise exception
      'TEST_FAILED: initial occurrence_at must equal starts_at';

  end if;


  -- ==========================================================
  -- 17. IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.activate_student_semester_plan(
      v_regular_plan_id
    );


  if (v_result ->> 'changed')::boolean <>
     false then

    raise exception
      'TEST_FAILED: second regular activation should be no-op';

  end if;


  if (v_result ->> 'rightCount')::integer <> 4
     or
     (v_result ->> 'lessonCount')::integer <> 4 then

    raise exception
      'TEST_FAILED: second activation returned wrong counts';

  end if;


  -- Ensure no duplicates were created.
  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_regular_semester_id

    and r.origin =
        'regular_base'::public.lesson_right_origin;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: regular activation duplicated rights';
  end if;


  -- ==========================================================
  -- 18. CROSS-BRANCH MANAGER DENIED
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_other_manager_id::text,
    true
  );


  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
        v_other_manager_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.activate_student_semester_plan(
      v_regular_plan_id
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
      'TEST_FAILED: cross-branch manager activated plan';
  end if;


  -- ==========================================================
  -- 19. FLEX ACTIVATION
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );


  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
        v_manager_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  v_result :=
    public.activate_student_semester_plan(
      v_flex_plan_id
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: flex plan should activate';
  end if;


  if (
    v_result
      -> 'materialization'
      ->> 'totalCount'
  )::integer <> 8 then

    raise exception
      'TEST_FAILED: flex plan expected 8 rights';
  end if;


  -- ==========================================================
  -- 20. FLEX RIGHTS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.student_id =
        v_student_id

    and r.source_semester_id =
        v_flex_semester_id

    and r.usable_semester_id =
        v_flex_semester_id

    and r.origin =
        'flex_base'::public.lesson_right_origin

    and r.status =
        'available'::public.lesson_right_status

    and r.duration_minutes = 30;


  if v_count <> 8 then
    raise exception
      'TEST_FAILED: expected exactly 8 available flex rights, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 21. ACTIVATING FUTURE FLEX PLAN MUST NOT CHANGE
  -- CURRENT students.student_type
  -- ==========================================================

  if (
    select s.student_type
    from public.students s
    where s.id = v_student_id
  ) is distinct from
    v_original_student_type then

    raise exception
      'TEST_FAILED: semester plan activation changed current student_type';

  end if;


  -- ==========================================================
  -- 22. FLEX IDEMPOTENCY
  -- ==========================================================

  v_result :=
    public.activate_student_semester_plan(
      v_flex_plan_id
    );


  if (v_result ->> 'changed')::boolean <>
     false then

    raise exception
      'TEST_FAILED: second flex activation should be no-op';
  end if;


  if (
    v_result
      -> 'materialization'
      ->> 'insertedCount'
  )::integer <> 0 then

    raise exception
      'TEST_FAILED: second flex activation inserted rights';
  end if;


  -- ==========================================================
  -- 23. NO WORK HOURS = STRICT FAILURE
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id = v_manager_id;


  v_denied := false;


  begin

    perform public.activate_student_semester_plan(
      v_no_hours_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: regular materialization without work hours succeeded';
  end if;


  -- Failed activation must stay PLANNED.
  if not exists (
    select 1
    from public.student_semester_plans sp

    where sp.id =
          v_no_hours_plan_id

      and sp.status =
          'planned'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: failed no-hours plan did not remain planned';
  end if;


  -- Failed statement must leave no regular rights.
  if exists (
    select 1
    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.source_semester_id =
          v_no_hours_semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) then

    raise exception
      'TEST_FAILED: failed no-hours activation left rights';
  end if;


  -- ==========================================================
  -- 24. RESTORE WORK HOURS
  -- ==========================================================

  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_manager_id,
    1,
    time '02:00',
    time '05:00'
  );


  -- ==========================================================
  -- 25. BLOCK ONE OCCURRENCE
  -- ==========================================================

  insert into public.blocked_periods (
    teacher_id,
    starts_at,
    ends_at,
    reason,
    created_by
  )
  values (
    v_manager_id,

    timestamptz
      '2099-07-13 03:00:00+09',

    timestamptz
      '2099-07-13 03:30:00+09',

    'remote materialization blocked test',

    v_manager_id
  );


  v_denied := false;


  begin

    perform public.activate_student_semester_plan(
      v_blocked_plan_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_OCCURRENCE_BLOCKED' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: blocked regular occurrence was materialized';
  end if;


  if not exists (
    select 1
    from public.student_semester_plans sp

    where sp.id =
          v_blocked_plan_id

      and sp.status =
          'planned'::public.student_semester_plan_status
  ) then

    raise exception
      'TEST_FAILED: blocked failure did not leave plan planned';
  end if;


  if exists (
    select 1
    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.source_semester_id =
          v_blocked_semester_id

      and r.origin =
          'regular_base'::public.lesson_right_origin
  ) then

    raise exception
      'TEST_FAILED: blocked activation left partial rights';
  end if;


  -- ==========================================================
  -- 26. AUDIT
  --
  -- Successful unique activations:
  --   regular = 1
  --   flex    = 1
  --
  -- Idempotent calls and failed calls must not add events.
  -- ==========================================================

  select count(*)::integer
  into v_audit_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.event_type =
        'SEMESTER_PLAN_ACTIVATED'

    and a.semester_id in (
      v_regular_semester_id,
      v_flex_semester_id,
      v_no_hours_semester_id,
      v_blocked_semester_id
    );


  if v_audit_count <> 2 then
    raise exception
      'TEST_FAILED: expected exactly 2 activation audit events, got %',
      v_audit_count;
  end if;

end;
$$;


select
  'PASS: semester activation / regular 4 lessons / instructional break / numbering / idempotency / flex N rights / strict availability / rollback / branch / audit'
  as test_result;

rollback;
