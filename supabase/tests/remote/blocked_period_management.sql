begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_other_manager_id uuid;
  v_student_id uuid;

  v_teacher_id uuid;

  v_lesson_id uuid;
  v_blocked_period_id uuid;

  v_result jsonb;

  v_original_lesson_start timestamptz;
  v_original_lesson_end timestamptz;
  v_original_lesson_duration integer;

  v_denied boolean;

  v_before_audit_count integer;
  v_after_audit_count integer;
begin

  -- ==========================================================
  -- 1. SAME-BRANCH MANAGER
  --
  -- Every manager is also a teacher entity in v3,
  -- so the manager themselves can be the test teacher.
  -- ==========================================================

  select
    p.id,
    p.branch_id
  into
    v_manager_id,
    v_branch_id
  from public.profiles p
  join public.teachers t
    on t.id = p.id
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
  order by p.created_at
  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active manager with teacher row';
  end if;


  v_teacher_id := v_manager_id;


  -- ==========================================================
  -- 2. ACTIVE SAME-BRANCH STUDENT
  -- ==========================================================

  select p.id
  into v_student_id
  from public.profiles p
  join public.students s
    on s.id = p.id
  where p.role = 'student'::public.user_role
    and p.is_active = true
    and p.branch_id = v_branch_id
    and s.status = 'active'::public.student_status
  order by p.created_at
  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active same-branch student';
  end if;


  -- ==========================================================
  -- 3. OTHER-BRANCH MANAGER
  -- ==========================================================

  select p.id
  into v_other_manager_id
  from public.profiles p
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
    and p.branch_id <> v_branch_id
  order by p.created_at
  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 4. TEST LESSON
  --
  -- Far-future standalone lesson keeps this test independent
  -- from regular-series/materialization logic.
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
    timestamptz '2099-02-02 10:00:00+09',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning
    id,
    starts_at,
    ends_at,
    duration_minutes
  into
    v_lesson_id,
    v_original_lesson_start,
    v_original_lesson_end,
    v_original_lesson_duration;


  -- ==========================================================
  -- 5. AUDIT BASELINE
  -- ==========================================================

  select count(*)::integer
  into v_before_audit_count
  from public.audit_events a
  where a.subject_profile_id = v_teacher_id
    and a.event_type in (
      'TEACHER_BLOCKED_PERIOD_CREATED',
      'TEACHER_BLOCKED_PERIOD_UPDATED',
      'TEACHER_BLOCKED_PERIOD_DELETED'
    );


  -- ==========================================================
  -- 6. SAME-BRANCH MANAGER JWT
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
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 7. CREATE BLOCKED PERIOD
  --
  -- Existing lesson:
  --   10:00 ~ 10:30
  --
  -- Block:
  --   09:30 ~ 10:15
  --
  -- Must NOT mutate lesson.
  -- Must return overlap warning.
  -- ==========================================================

  v_result :=
    public.upsert_teacher_blocked_period(
      v_teacher_id,
      timestamptz '2099-02-02 09:30:00+09',
      timestamptz '2099-02-02 10:15:00+09',
      'remote blocked-period test',
      null
    );


  v_blocked_period_id :=
    (v_result ->> 'blockedPeriodId')::uuid;


  if v_blocked_period_id is null then
    raise exception
      'TEST_FAILED: blocked period id was not returned';
  end if;


  if (v_result ->> 'scheduledLessonOverlapCount')::integer <> 1 then
    raise exception
      'TEST_FAILED: expected 1 overlapping lesson, got %',
      v_result ->> 'scheduledLessonOverlapCount';
  end if;


  if not (
    (v_result -> 'warningCodes')
      ? 'FORESTRING_BLOCKED_PERIOD_HAS_EXISTING_LESSONS'
  ) then
    raise exception
      'TEST_FAILED: existing-lesson warning missing';
  end if;


  -- ==========================================================
  -- 8. EXISTING LESSON MUST BE UNCHANGED
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id = v_lesson_id
      and l.starts_at =
          v_original_lesson_start
      and l.ends_at =
          v_original_lesson_end
      and l.duration_minutes =
          v_original_lesson_duration
      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: creating blocked period mutated lesson';

  end if;


  -- ==========================================================
  -- 9. UPDATE BLOCKED PERIOD
  -- ==========================================================

  v_result :=
    public.upsert_teacher_blocked_period(
      v_teacher_id,
      timestamptz '2099-02-02 09:45:00+09',
      timestamptz '2099-02-02 10:30:00+09',
      'updated remote blocked-period test',
      v_blocked_period_id
    );


  if (v_result ->> 'blockedPeriodId')::uuid <>
     v_blocked_period_id then

    raise exception
      'TEST_FAILED: update changed blocked period identity';

  end if;


  if (v_result ->> 'scheduledLessonOverlapCount')::integer <> 1 then
    raise exception
      'TEST_FAILED: updated blocked period should still overlap 1 lesson';
  end if;


  if not exists (
    select 1
    from public.blocked_periods bp
    where bp.id = v_blocked_period_id
      and bp.teacher_id = v_teacher_id
      and bp.starts_at =
          timestamptz '2099-02-02 09:45:00+09'
      and bp.ends_at =
          timestamptz '2099-02-02 10:30:00+09'
      and bp.reason =
          'updated remote blocked-period test'
  ) then

    raise exception
      'TEST_FAILED: blocked period update was not persisted';

  end if;


  -- ==========================================================
  -- 10. OVERLAPPING BLOCKED PERIOD MUST FAIL
  -- ==========================================================

  v_denied := false;


  begin

    perform public.upsert_teacher_blocked_period(
      v_teacher_id,
      timestamptz '2099-02-02 10:15:00+09',
      timestamptz '2099-02-02 10:45:00+09',
      'must fail',
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_BLOCKED_PERIOD_OVERLAP' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: overlapping blocked period was accepted';
  end if;


  -- ==========================================================
  -- 11. INVALID RANGE MUST FAIL
  -- ==========================================================

  v_denied := false;


  begin

    perform public.upsert_teacher_blocked_period(
      v_teacher_id,
      timestamptz '2099-02-02 12:00:00+09',
      timestamptz '2099-02-02 11:00:00+09',
      null,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_INVALID_BLOCKED_PERIOD_RANGE' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: invalid blocked period range was accepted';
  end if;


  -- ==========================================================
  -- 12. CROSS-BRANCH MANAGER MAY NOT DELETE
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

    perform public.delete_teacher_blocked_period(
      v_blocked_period_id
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
      'TEST_FAILED: cross-branch manager deleted blocked period';
  end if;


  -- Row must still exist.
  if not exists (
    select 1
    from public.blocked_periods bp
    where bp.id = v_blocked_period_id
  ) then

    raise exception
      'TEST_FAILED: denied delete still removed blocked period';

  end if;


  -- ==========================================================
  -- 13. SAME-BRANCH MANAGER MAY DELETE
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
    public.delete_teacher_blocked_period(
      v_blocked_period_id
    );


  if (v_result ->> 'deleted')::boolean <> true then
    raise exception
      'TEST_FAILED: blocked period delete did not succeed';
  end if;


  if exists (
    select 1
    from public.blocked_periods bp
    where bp.id = v_blocked_period_id
  ) then

    raise exception
      'TEST_FAILED: blocked period remains after delete';

  end if;


  -- ==========================================================
  -- 14. LESSON MUST STILL BE UNCHANGED AFTER FULL CRUD
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id = v_lesson_id
      and l.starts_at =
          v_original_lesson_start
      and l.ends_at =
          v_original_lesson_end
      and l.duration_minutes =
          v_original_lesson_duration
      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: blocked-period CRUD mutated existing lesson';

  end if;


  -- ==========================================================
  -- 15. EXACTLY THREE AUDIT EVENTS
  --
  -- create
  -- update
  -- delete
  --
  -- Failed overlap / invalid input / cross-branch delete
  -- must not generate audit rows.
  -- ==========================================================

  select count(*)::integer
  into v_after_audit_count
  from public.audit_events a
  where a.subject_profile_id = v_teacher_id
    and a.event_type in (
      'TEACHER_BLOCKED_PERIOD_CREATED',
      'TEACHER_BLOCKED_PERIOD_UPDATED',
      'TEACHER_BLOCKED_PERIOD_DELETED'
    );


  if v_after_audit_count
     - v_before_audit_count <> 3 then

    raise exception
      'TEST_FAILED: expected 3 audit events, got %',
      v_after_audit_count - v_before_audit_count;

  end if;

end;
$$;


select
  'PASS: blocked period create / update / delete / overlap / branch / warning / lesson preservation / audit'
  as test_result;

rollback;
