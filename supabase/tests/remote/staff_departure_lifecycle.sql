begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_future_date date :=
    v_today + 7;

  v_master_id uuid;

  v_manager_id uuid;

  v_target_id uuid;
  v_target_branch_id uuid;
  v_target_original_role public.user_role;

  v_student_id uuid;

  v_test_lesson_id uuid;
  v_test_lesson_start timestamptz;
  v_test_lesson_end timestamptz;

  v_result jsonb;
  v_blockers jsonb;

  v_before integer;
  v_after integer;

  v_denied boolean;
begin

  -- ==========================================================
  -- 1. FIXTURES
  --
  -- Pick a CLEAN active teacher:
  --   no current/future assignment
  --   no current/future series
  --   no current/future scheduled lesson
  --
  -- This lets us test successful finalization deterministically
  -- without rewriting real operational data.
  -- ==========================================================

  select p.id
  into v_master_id

  from public.profiles p

  where p.role =
        'master'::public.user_role

    and p.is_active = true

  order by p.created_at
  limit 1;


  if v_master_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master';
  end if;


  select
    p.id,
    p.branch_id,
    p.role

  into
    v_target_id,
    v_target_branch_id,
    v_target_original_role

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.role =
        'teacher'::public.user_role

    and p.is_active = true

    and p.branch_id is not null

    and t.withdrawal_date is null

    -- Same branch needs an active manager for manager auth tests.
    and exists (
      select 1
      from public.profiles m
      where m.role =
            'manager'::public.user_role
        and m.is_active = true
        and m.branch_id =
            p.branch_id
    )

    -- No assignment surviving into today.
    and not exists (
      select 1

      from public.teacher_student_assignments a

      where a.teacher_id =
            p.id

        and (
          a.ends_on is null
          or a.ends_on >=
             v_today
        )
    )

    -- No series surviving into today.
    and not exists (
      select 1

      from public.lesson_series ls

      where ls.teacher_id =
            p.id

        and (
          ls.effective_until is null
          or ls.effective_until >=
             v_today
        )
    )

    -- No actual scheduled lesson today or later.
    and not exists (
      select 1

      from public.lessons l

      where l.teacher_id =
            p.id

        and l.status =
            'scheduled'::public.lesson_status

        and (
          l.starts_at
          at time zone 'Asia/Seoul'
        )::date >=
            v_today
    )

  order by p.created_at desc
  limit 1;


  if v_target_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: clean active teacher in manager branch';
  end if;


  select p.id
  into v_manager_id

  from public.profiles p

  where p.role =
        'manager'::public.user_role

    and p.is_active = true

    and p.branch_id =
        v_target_branch_id

  order by p.created_at
  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active same-branch manager';
  end if;


  -- Active student used only for trigger tests / synthetic lesson.
  select s.id
  into v_student_id

  from public.students s

  join public.profiles p
    on p.id = s.id

  where p.branch_id =
        v_target_branch_id

    and p.is_active = true

    and s.status =
        'active'::public.student_status

    and s.withdrawal_date is null

  order by p.created_at
  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active same-branch student';
  end if;


  -- ==========================================================
  -- 2. FUNCTION PRIVILEGES
  -- ==========================================================

  if
    has_function_privilege(
      'anon',
      'public.schedule_staff_departure(uuid,date)',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'anon',
      'public.cancel_staff_departure(uuid)',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'anon',
      'public.get_staff_departure_blockers(uuid)',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'anon',
      'public.finalize_staff_departure(uuid)',
      'EXECUTE'
    )
  then

    raise exception
      'TEST_FAILED: anon can execute staff departure RPC';

  end if;


  if not
    has_function_privilege(
      'authenticated',
      'public.schedule_staff_departure(uuid,date)',
      'EXECUTE'
    )
    or not
    has_function_privilege(
      'authenticated',
      'public.cancel_staff_departure(uuid)',
      'EXECUTE'
    )
    or not
    has_function_privilege(
      'authenticated',
      'public.get_staff_departure_blockers(uuid)',
      'EXECUTE'
    )
    or not
    has_function_privilege(
      'authenticated',
      'public.finalize_staff_departure(uuid)',
      'EXECUTE'
    )
  then

    raise exception
      'TEST_FAILED: authenticated RPC grant missing';

  end if;


  if
    has_function_privilege(
      'authenticated',
      'public.assert_assignment_before_teacher_withdrawal()',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'authenticated',
      'public.assert_series_before_teacher_withdrawal()',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'authenticated',
      'public.assert_lesson_before_teacher_withdrawal()',
      'EXECUTE'
    )
    or
    has_function_privilege(
      'authenticated',
      'public.assert_staff_role_change_without_pending_departure()',
      'EXECUTE'
    )
  then

    raise exception
      'TEST_FAILED: authenticated can execute internal trigger function';

  end if;


  -- ==========================================================
  -- 3. NORMAL TEACHER CANNOT SCHEDULE OWN DEPARTURE
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_target_id::text,
    true
  );


  v_denied := false;


  begin

    perform public.schedule_staff_departure(
      v_target_id,
      v_future_date
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STAFF_DEPARTURE_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher scheduled own departure';
  end if;


  -- ==========================================================
  -- 4. SAME-BRANCH MANAGER MAY SCHEDULE TEACHER
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );


  select count(*)::integer
  into v_before

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_SCHEDULED';


  v_result :=
    public.schedule_staff_departure(
      v_target_id,
      v_future_date
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: manager schedule returned changed=false';

  end if;


  if not exists (
    select 1

    from public.teachers t

    where t.id =
          v_target_id

      and t.withdrawal_date =
          v_future_date
  ) then

    raise exception
      'TEST_FAILED: withdrawal_date not stored';
  end if;


  select count(*)::integer
  into v_after

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_SCHEDULED';


  if v_after <> v_before + 1 then
    raise exception
      'TEST_FAILED: schedule audit missing';
  end if;


  -- ==========================================================
  -- 5. SAME SCHEDULE IS IDEMPOTENT
  -- ==========================================================

  v_before :=
    v_after;


  v_result :=
    public.schedule_staff_departure(
      v_target_id,
      v_future_date
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: duplicate schedule not idempotent';
  end if;


  select count(*)::integer
  into v_after

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_SCHEDULED';


  if v_after <> v_before then
    raise exception
      'TEST_FAILED: idempotent schedule created audit';
  end if;


  -- ==========================================================
  -- 6. ROLE CHANGE BLOCKED WHILE DEPARTURE PENDING
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
    true
  );


  v_denied := false;


  begin

    perform public.change_staff_role(
      v_target_id,
      'manager'::public.user_role
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STAFF_DEPARTURE_PENDING' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: staff role changed while departure pending';
  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_target_id

      and p.role =
          v_target_original_role
  ) then

    raise exception
      'TEST_FAILED: failed role change mutated role';
  end if;


  -- ==========================================================
  -- 7. MANAGER MAY CANCEL FUTURE DEPARTURE
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );


  v_result :=
    public.cancel_staff_departure(
      v_target_id
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: manager cancel failed';
  end if;


  if exists (
    select 1

    from public.teachers t

    where t.id =
          v_target_id

      and t.withdrawal_date
          is not null
  ) then

    raise exception
      'TEST_FAILED: withdrawal_date remained after cancel';
  end if;


  -- Second cancel = clean no-op.
  v_result :=
    public.cancel_staff_departure(
      v_target_id
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: duplicate cancel not idempotent';
  end if;


  -- ==========================================================
  -- 8. MANAGER MAY NOT SCHEDULE A MANAGER
  -- ==========================================================

  v_denied := false;


  begin

    perform public.schedule_staff_departure(
      v_manager_id,
      v_future_date
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STAFF_DEPARTURE_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: manager scheduled manager departure';
  end if;


  -- ==========================================================
  -- 9. CREATE ONE FUTURE LESSON BEFORE SCHEDULING DEPARTURE
  --
  -- 2099 fixture avoids collision with real timetables.
  -- makeup requires no series/right.
  -- ==========================================================

  v_test_lesson_start :=
    pg_catalog.make_timestamptz(
      2099,
      1,
      15,
      3,
      0,
      0,
      'Asia/Seoul'
    );


  v_test_lesson_end :=
    v_test_lesson_start
    + pg_catalog.make_interval(
        mins => 15
      );


  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    ends_at,
    lesson_type,
    status,
    branch_id
  )
  values (
    v_student_id,
    v_target_id,
    v_test_lesson_start,
    15,
    v_test_lesson_end,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_target_branch_id
  )
  returning id
  into v_test_lesson_id;


  -- ==========================================================
  -- 10. MASTER SCHEDULES EFFECTIVE TODAY
  --
  -- Existing future lesson is NOT deleted.
  -- It becomes an explicit blocker.
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
    true
  );


  v_result :=
    public.schedule_staff_departure(
      v_target_id,
      v_today
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: master same-day schedule failed';
  end if;


  if (
    v_result
    ->> 'scheduledLessonCount'
  )::integer < 1 then

    raise exception
      'TEST_FAILED: scheduled future lesson not reported as blocker';
  end if;


  if coalesce(
       (
         v_result
         ->> 'canFinalize'
       )::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: departure incorrectly marked finalizable';
  end if;


  -- Existing lesson must still exist.
  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_test_lesson_id

      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: scheduling departure deleted existing lesson';
  end if;


  -- ==========================================================
  -- 11. PUBLIC BLOCKER RPC
  -- ==========================================================

  v_blockers :=
    public.get_staff_departure_blockers(
      v_target_id
    );


  if (
    v_blockers
    ->> 'scheduledLessonCount'
  )::integer < 1 then

    raise exception
      'TEST_FAILED: blocker RPC missed lesson';
  end if;


  if coalesce(
       (
         v_blockers
         ->> 'canFinalize'
       )::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: blocker RPC returned canFinalize=true';
  end if;


  -- ==========================================================
  -- 12. FINALIZE MUST FAIL WHILE BLOCKED
  -- ==========================================================

  v_denied := false;


  begin

    perform public.finalize_staff_departure(
      v_target_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STAFF_DEPARTURE_BLOCKED' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: blocked departure finalized';
  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_target_id

      and p.is_active = true
  ) then

    raise exception
      'TEST_FAILED: blocked finalize deactivated staff';
  end if;


  -- ==========================================================
  -- 13. TABLE-LEVEL ASSIGNMENT HARD GUARD
  --
  -- Trigger runs before overlap/exclusion constraints.
  -- ==========================================================

  v_denied := false;


  begin

    insert into public.teacher_student_assignments (
      teacher_id,
      student_id,
      starts_on,
      ends_on,
      branch_id
    )
    values (
      v_target_id,
      v_student_id,
      v_today,
      v_today,
      v_target_branch_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_ASSIGNMENT_ON_OR_AFTER_TEACHER_WITHDRAWAL' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: assignment on/after departure accepted';
  end if;


  -- ==========================================================
  -- 14. TABLE-LEVEL SERIES HARD GUARD
  -- ==========================================================

  v_denied := false;


  begin

    insert into public.lesson_series (
      student_id,
      teacher_id,
      weekday,
      start_time,
      duration_minutes,
      effective_from,
      effective_until,
      branch_id,
      schedule_slot_id
    )
    values (
      v_student_id,
      v_target_id,
      1,
      time '03:00',
      15,
      v_today,
      v_today,
      v_target_branch_id,
      null
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_SERIES_ON_OR_AFTER_TEACHER_WITHDRAWAL' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: series on/after departure accepted';
  end if;


  -- ==========================================================
  -- 15. TABLE-LEVEL LESSON HARD GUARD
  -- ==========================================================

  v_denied := false;


  begin

    insert into public.lessons (
      student_id,
      teacher_id,
      starts_at,
      duration_minutes,
      ends_at,
      lesson_type,
      status,
      branch_id
    )
    values (
      v_student_id,
      v_target_id,
      v_test_lesson_start
        + pg_catalog.make_interval(
            hours => 1
          ),
      15,
      v_test_lesson_end
        + pg_catalog.make_interval(
            hours => 1
          ),
      'makeup'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_target_branch_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_ON_OR_AFTER_TEACHER_WITHDRAWAL' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: lesson on/after departure accepted';
  end if;


  -- ==========================================================
  -- 16. RESOLVE THE ONLY BLOCKER EXPLICITLY
  --
  -- Departure finalizer itself must not delete it.
  -- Admin workflow resolves it first.
  -- ==========================================================

  delete
  from public.lessons
  where id =
        v_test_lesson_id;


  v_blockers :=
    public.get_staff_departure_blockers(
      v_target_id
    );


  if coalesce(
       (
         v_blockers
         ->> 'assignmentCount'
       )::integer,
       0
     ) <> 0
     or
     coalesce(
       (
         v_blockers
         ->> 'seriesCount'
       )::integer,
       0
     ) <> 0
     or
     coalesce(
       (
         v_blockers
         ->> 'scheduledLessonCount'
       )::integer,
       0
     ) <> 0 then

    raise exception
      'TEST_FAILED: clean teacher still has blockers: %',
      v_blockers;

  end if;


  if coalesce(
       (
         v_blockers
         ->> 'canFinalize'
       )::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: clean departure not finalizable';
  end if;


  -- ==========================================================
  -- 17. FINALIZE
  -- ==========================================================

  select count(*)::integer
  into v_before

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_FINALIZED';


  v_result :=
    public.finalize_staff_departure(
      v_target_id
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       false
     ) is distinct from true then

    raise exception
      'TEST_FAILED: clean finalization returned changed=false';
  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_target_id

      and p.is_active = false
  ) then

    raise exception
      'TEST_FAILED: finalized staff still active';
  end if;


  -- Teacher entity and UUID must remain.
  if not exists (
    select 1

    from public.teachers t

    where t.id =
          v_target_id

      and t.withdrawal_date =
          v_today
  ) then

    raise exception
      'TEST_FAILED: teacher entity/history lost during finalization';
  end if;


  select count(*)::integer
  into v_after

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_FINALIZED';


  if v_after <> v_before + 1 then
    raise exception
      'TEST_FAILED: finalization audit missing';
  end if;


  -- ==========================================================
  -- 18. FINALIZE IS IDEMPOTENT
  -- ==========================================================

  v_before :=
    v_after;


  v_result :=
    public.finalize_staff_departure(
      v_target_id
    );


  if coalesce(
       (v_result ->> 'changed')::boolean,
       true
     ) is distinct from false then

    raise exception
      'TEST_FAILED: second finalize not idempotent';
  end if;


  select count(*)::integer
  into v_after

  from public.audit_events a

  where a.subject_profile_id =
        v_target_id

    and a.event_type =
        'STAFF_DEPARTURE_FINALIZED';


  if v_after <> v_before then
    raise exception
      'TEST_FAILED: idempotent finalize created audit';
  end if;

end;
$$;


select
  'PASS: staff departure schedule/cancel/idempotency/manager scope/role guard/blockers/table hard guards/finalize/audit/history preservation'
  as test_result;

rollback;
