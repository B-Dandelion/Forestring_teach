begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_lesson_id uuid;
  v_teacher_collision_lesson_id uuid;
  v_student_collision_lesson_id uuid;

  v_test_date date := date '2099-01-05';
  v_weekday smallint;

  v_result jsonb;

  v_original_student_id uuid;
  v_original_teacher_id uuid;
  v_original_branch_id uuid;
  v_original_series_id uuid;
  v_original_occurrence_at timestamptz;
  v_original_right_id uuid;
  v_original_type public.lesson_type;

  v_current_start timestamptz;
  v_current_duration integer;

  v_denied boolean;
  v_audit_count integer;
begin

  -- ==========================================================
  -- 1. FIXTURE
  --
  -- Need:
  --   active manager
  --   active teacher in same branch
  --   active student in same branch
  --
  -- Manager already has a teachers row in v3.
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
    v_student_id

  from public.profiles manager_profile

  join public.teachers manager_teacher
    on manager_teacher.id = manager_profile.id

  join public.profiles teacher_profile
    on teacher_profile.branch_id =
       manager_profile.branch_id
   and teacher_profile.role =
       'teacher'::public.user_role
   and teacher_profile.is_active = true

  join public.teachers teacher_entity
    on teacher_entity.id = teacher_profile.id

  join public.profiles student_profile
    on student_profile.branch_id =
       manager_profile.branch_id
   and student_profile.role =
       'student'::public.user_role
   and student_profile.is_active = true

  join public.students student_entity
    on student_entity.id = student_profile.id
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
      'TEST_FIXTURE_REQUIRED: manager + teacher + student in same branch';
  end if;


  -- ==========================================================
  -- 2. CONTROL TEST TEACHER AVAILABILITY
  --
  -- Everything rolls back later.
  -- ==========================================================

  v_weekday :=
    extract(
      isodow
      from (
        timestamptz '2099-01-05 10:00:00+09'
        at time zone 'Asia/Seoul'
      )
    )::smallint;


  delete from public.teacher_work_hours
  where teacher_id = v_teacher_id;


  delete from public.blocked_periods
  where teacher_id = v_teacher_id;


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_id,
    v_weekday,
    time '09:00',
    time '18:00'
  );


  -- ==========================================================
  -- 3. PRIMARY TEST LESSON
  --
  -- makeup is used here so this test is independent from
  -- unfinished regular-materialization logic.
  -- ==========================================================

  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    timestamptz '2099-01-05 10:00:00+09',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_lesson_id;


  -- Same teacher + same student at 14:00.
  -- Used to prove teacher collision is hard-blocked.
  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    timestamptz '2099-01-05 14:00:00+09',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_teacher_collision_lesson_id;


  -- Same student, DIFFERENT teacher.
  --
  -- The manager is also a teacher entity.
  -- Used to prove student collision independently.
  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_manager_id,
    timestamptz '2099-01-05 16:00:00+09',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_student_collision_lesson_id;


  -- ==========================================================
  -- 4. SNAPSHOT IMMUTABLE LESSON IDENTITY
  -- ==========================================================

  select
    l.student_id,
    l.teacher_id,
    l.branch_id,
    l.series_id,
    l.occurrence_at,
    l.lesson_right_id,
    l.lesson_type
  into
    v_original_student_id,
    v_original_teacher_id,
    v_original_branch_id,
    v_original_series_id,
    v_original_occurrence_at,
    v_original_right_id,
    v_original_type
  from public.lessons l
  where l.id = v_lesson_id;


  -- ==========================================================
  -- 5. TEACHER MAY EDIT OWN LESSON
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
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
      'sub', v_teacher_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_result :=
    public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 11:00:00+09',
      30,
      false,
      'remote test - teacher'
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: teacher own lesson update should succeed';
  end if;


  -- ==========================================================
  -- 6. SAME-BRANCH MANAGER MAY EDIT
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


  v_result :=
    public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 11:30:00+09',
      30,
      false,
      'remote test - manager'
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: same-branch manager update should succeed';
  end if;


  -- ==========================================================
  -- 7. STUDENT MAY NOT CALL ADMINISTRATIVE EDIT RPC
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;

  begin

    perform public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 11:45:00+09',
      30,
      false,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_UPDATE_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: student administrative lesson edit was accepted';
  end if;


  -- ==========================================================
  -- 8. TEACHER MAY NOT EDIT ANOTHER TEACHER'S LESSON
  --
  -- v_student_collision_lesson_id is taught by manager.
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_teacher_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;

  begin

    perform public.update_lesson_once(
      v_student_collision_lesson_id,
      timestamptz '2099-01-05 16:30:00+09',
      30,
      false,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_TEACHER_LESSON_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher edited another teacher lesson';
  end if;


  -- ==========================================================
  -- 9. INVALID DURATION IS HARD ERROR
  -- ==========================================================

  v_denied := false;

  begin

    perform public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 12:00:00+09',
      20,
      false,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_INVALID_LESSON_DURATION' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: non-15-minute duration was accepted';
  end if;


  -- ==========================================================
  -- 10. TEACHER ACTUAL OVERLAP = HARD ERROR
  --
  -- Existing lesson:
  --   same teacher @ 14:00
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

    perform public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 14:00:00+09',
      30,
      true,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_TEACHER_LESSON_OVERLAP' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher lesson overlap was accepted';
  end if;


  -- ==========================================================
  -- 11. STUDENT ACTUAL OVERLAP = HARD ERROR
  --
  -- Existing lesson:
  --   same student / different teacher @ 16:00
  -- ==========================================================

  v_denied := false;

  begin

    perform public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 16:00:00+09',
      30,
      true,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STUDENT_LESSON_OVERLAP' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: student lesson overlap was accepted';
  end if;


  -- ==========================================================
  -- 12. CREATE BLOCKED PERIOD FOR WARNING TEST
  -- ==========================================================

  insert into public.blocked_periods (
    teacher_id,
    starts_at,
    ends_at,
    reason,
    created_by
  )
  values (
    v_teacher_id,
    timestamptz '2099-01-05 12:00:00+09',
    timestamptz '2099-01-05 13:00:00+09',
    'remote test block',
    v_manager_id
  );


  -- ==========================================================
  -- 13. WARNING CALL MUST NOT MUTATE
  --
  -- 12:00~12:45:
  --   inside work hours
  --   overlaps blocked period
  --   45 min = nonstandard
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_teacher_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_result :=
    public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 12:00:00+09',
      45,
      false,
      'warning confirmation test'
    );


  if (v_result ->> 'requiresConfirmation')::boolean <> true then
    raise exception
      'TEST_FAILED: warning update did not request confirmation';
  end if;


  if (v_result ->> 'changed')::boolean <> false then
    raise exception
      'TEST_FAILED: warning-only call mutated lesson';
  end if;


  if not (
    (v_result -> 'warningCodes')
      ? 'FORESTRING_OVERLAPS_BLOCKED_PERIOD'
  ) then
    raise exception
      'TEST_FAILED: blocked-period warning missing';
  end if;


  if not (
    (v_result -> 'warningCodes')
      ? 'FORESTRING_NONSTANDARD_DURATION'
  ) then
    raise exception
      'TEST_FAILED: nonstandard-duration warning missing';
  end if;


  select
    l.starts_at,
    l.duration_minutes
  into
    v_current_start,
    v_current_duration
  from public.lessons l
  where l.id = v_lesson_id;


  if v_current_start <>
       timestamptz '2099-01-05 11:30:00+09'
     or
     v_current_duration <> 30 then

    raise exception
      'TEST_FAILED: lesson changed before warning confirmation';
  end if;


  -- ==========================================================
  -- 14. CONFIRMED WARNING UPDATE MUST SUCCEED
  -- ==========================================================

  v_result :=
    public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 12:00:00+09',
      45,
      true,
      'warning confirmation test'
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: confirmed warning update did not succeed';
  end if;


  if (v_result ->> 'requiresConfirmation')::boolean <> false then
    raise exception
      'TEST_FAILED: confirmed update still requests confirmation';
  end if;


  -- ==========================================================
  -- 15. UNCHANGED SAVE MUST BE NO-OP
  --
  -- Even though current lesson is:
  --   blocked
  --   45-minute nonstandard
  --
  -- unchanged save must not ask again.
  -- ==========================================================

  v_result :=
    public.update_lesson_once(
      v_lesson_id,
      timestamptz '2099-01-05 12:00:00+09',
      45,
      false,
      null
    );


  if (v_result ->> 'changed')::boolean <> false
     or
     (v_result ->> 'requiresConfirmation')::boolean <> false then

    raise exception
      'TEST_FAILED: unchanged lesson save was not a clean no-op';
  end if;


  -- ==========================================================
  -- 16. LESSON DOMAIN IDENTITY MUST NOT CHANGE
  -- ==========================================================

  if exists (
    select 1
    from public.lessons l
    where l.id = v_lesson_id

      and (
        l.student_id is distinct from
          v_original_student_id

        or l.teacher_id is distinct from
          v_original_teacher_id

        or l.branch_id is distinct from
          v_original_branch_id

        or l.series_id is distinct from
          v_original_series_id

        or l.occurrence_at is distinct from
          v_original_occurrence_at

        or l.lesson_right_id is distinct from
          v_original_right_id

        or l.lesson_type is distinct from
          v_original_type
      )
  ) then

    raise exception
      'TEST_FAILED: one-off update changed lesson identity';
  end if;


  -- ==========================================================
  -- 17. END TIME MUST BE DATABASE-DERIVED
  --
  -- 12:00 + 45 = 12:45 KST
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id = v_lesson_id
      and l.starts_at =
          timestamptz '2099-01-05 12:00:00+09'
      and l.ends_at =
          timestamptz '2099-01-05 12:45:00+09'
      and l.duration_minutes = 45
  ) then

    raise exception
      'TEST_FAILED: lesson final actual time is incorrect';
  end if;


  -- ==========================================================
  -- 18. AUDIT
  --
  -- Successful mutations:
  --   teacher 10:00 -> 11:00
  --   manager 11:00 -> 11:30
  --   confirmed 11:30 -> 12:00 / 45m
  --
  -- Expected = exactly 3.
  -- ==========================================================

  select count(*)::integer
  into v_audit_count
  from public.audit_events a
  where a.event_type =
        'LESSON_MANUALLY_UPDATED'

    and a.details ->> 'lessonId' =
        v_lesson_id::text;


  if v_audit_count <> 3 then
    raise exception
      'TEST_FAILED: expected 3 lesson audit events, got %',
      v_audit_count;
  end if;


  -- Confirm latest audit explicitly recorded warning override.
  if not exists (
    select 1
    from public.audit_events a
    where a.event_type =
          'LESSON_MANUALLY_UPDATED'

      and a.details ->> 'lessonId' =
          v_lesson_id::text

      and (
        a.details ->>
        'warningsOverridden'
      )::boolean = true

      and (
        a.details -> 'warningCodes'
      ) ? 'FORESTRING_OVERLAPS_BLOCKED_PERIOD'

      and (
        a.details -> 'warningCodes'
      ) ? 'FORESTRING_NONSTANDARD_DURATION'
  ) then

    raise exception
      'TEST_FAILED: warning override audit missing';
  end if;

end;
$$;


select
  'PASS: one-off lesson update / teacher / manager / permissions / collisions / warnings / identity / audit'
  as test_result;

rollback;
