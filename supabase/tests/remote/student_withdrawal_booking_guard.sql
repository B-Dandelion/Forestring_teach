begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_semester_id uuid;

  v_right_before_id uuid;
  v_right_on_id uuid;

  v_existing_before_lesson_id uuid;
  v_existing_after_lesson_id uuid;

  v_withdrawal_date date :=
    date '2111-06-20';

  v_before_date date :=
    date '2111-06-19';

  v_after_date date :=
    date '2111-06-21';

  v_before_weekday smallint;
  v_withdrawal_weekday smallint;

  v_result jsonb;
  v_count integer;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. FIXTURE
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


  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_student_id;


  update public.profiles
  set
    is_active =
      true,

    branch_id =
      v_branch_id

  where id =
        v_student_id;


  -- ==========================================================
  -- 2. TEST SEMESTER = EXACTLY 28 DAYS
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-WITHDRAWAL-GUARD-2111',
    date '2111-06-06',
    date '2111-07-03'
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 3. ISOLATE ASSIGNMENT
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id =
        v_student_id

    and starts_on >=
        date '2111-06-06';


  update public.teacher_student_assignments
  set ends_on =
      date '2111-06-05'

  where student_id =
        v_student_id

    and starts_on <
        date '2111-06-06'

    and (
      ends_on is null
      or ends_on >=
         date '2111-06-06'
    );


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    branch_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_id,
    v_student_id,
    v_branch_id,
    date '2111-06-06',
    null
  );


  -- ==========================================================
  -- 4. CONTROL WORK HOURS / BLOCKS / CLOSURES
  -- ==========================================================

  v_before_weekday :=
    extract(
      isodow
      from v_before_date
    )::smallint;


  v_withdrawal_weekday :=
    extract(
      isodow
      from v_withdrawal_date
    )::smallint;


  delete from public.teacher_work_hours
  where teacher_id =
        v_teacher_id;


  delete from public.blocked_periods
  where teacher_id =
        v_teacher_id;


  delete from public.closure_periods
  where branch_id =
        v_branch_id

    and starts_on <=
        v_after_date

    and ends_on >=
        v_before_date;


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values (
    v_teacher_id,
    v_before_weekday,
    time '10:00',
    time '12:00'
  );


  if v_withdrawal_weekday <>
     v_before_weekday then

    insert into public.teacher_work_hours (
      teacher_id,
      weekday,
      start_time,
      end_time
    )
    values (
      v_teacher_id,
      v_withdrawal_weekday,
      time '10:00',
      time '12:00'
    );

  end if;


  -- ==========================================================
  -- 5. TWO AVAILABLE FLEX RIGHTS
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
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    null,
    null,
    'flex_base'::public.lesson_right_origin,
    1,
    30,
    'available'::public.lesson_right_status,
    0,
    v_manager_id
  )
  returning id
  into v_right_before_id;


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
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    null,
    null,
    'flex_base'::public.lesson_right_origin,
    2,
    30,
    'available'::public.lesson_right_status,
    0,
    v_manager_id
  )
  returning id
  into v_right_on_id;


  -- ==========================================================
  -- 6. EXISTING LESSONS CREATED BEFORE WITHDRAWAL IS SCHEDULED
  --
  -- Scheduling withdrawal itself must NOT delete them.
  -- ==========================================================

  insert into public.lessons (
    student_id,
    teacher_id,
    branch_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    v_branch_id,
    (
      v_before_date + time '15:00'
    ) at time zone 'Asia/Seoul',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_existing_before_lesson_id;


  insert into public.lessons (
    student_id,
    teacher_id,
    branch_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    v_branch_id,
    (
      v_after_date + time '15:00'
    ) at time zone 'Asia/Seoul',
    30,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_existing_after_lesson_id;


  -- ==========================================================
  -- 7. MANAGER SCHEDULES WITHDRAWAL
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


  v_result :=
    public.schedule_student_withdrawal(
      v_student_id,
      v_withdrawal_date
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: withdrawal was not scheduled';

  end if;


  -- Existing future lesson must still exist.
  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_existing_after_lesson_id
  ) then

    raise exception
      'TEST_FAILED: scheduling withdrawal deleted existing future lesson';

  end if;


  -- ==========================================================
  -- 8. STUDENT LOGIN
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
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
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 9. DAY BEFORE WITHDRAWAL -> OPTIONS EXIST
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_before_id,
    v_before_date
  );


  if v_count <= 0 then

    raise exception
      'TEST_FAILED: day-before-withdrawal availability disappeared';

  end if;


  -- ==========================================================
  -- 10. WITHDRAWAL DATE -> ZERO OPTIONS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_on_id,
    v_withdrawal_date
  );


  if v_count <> 0 then

    raise exception
      'TEST_FAILED: withdrawal-date availability still visible';

  end if;


  -- ==========================================================
  -- 11. AFTER WITHDRAWAL -> ZERO OPTIONS
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_on_id,
    v_after_date
  );


  if v_count <> 0 then

    raise exception
      'TEST_FAILED: post-withdrawal availability still visible';

  end if;


  -- ==========================================================
  -- 12. FINAL BOOKING RPC ALSO REJECTS WITHDRAWAL DATE
  -- ==========================================================

  v_denied :=
    false;


  begin

    perform public.book_lesson_right(
      v_right_on_id,
      (
        v_withdrawal_date + time '10:00'
      ) at time zone 'Asia/Seoul'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: booking RPC accepted withdrawal-date lesson';

  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_on_id

      and r.status =
          'available'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: rejected withdrawal booking mutated right';

  end if;


  -- ==========================================================
  -- 13. DAY BEFORE WITHDRAWAL BOOKING SUCCEEDS
  -- ==========================================================

  v_result :=
    public.book_lesson_right(
      v_right_before_id,
      (
        v_before_date + time '10:00'
      ) at time zone 'Asia/Seoul'
    );


  if (v_result ->> 'lessonId') is null then

    raise exception
      'TEST_FAILED: valid pre-withdrawal booking failed';

  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_before_id

      and r.status =
          'reserved'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: pre-withdrawal booking did not reserve right';

  end if;


  -- ==========================================================
  -- 14. TABLE-LEVEL FINAL GUARD:
  -- DIRECT SCHEDULED INSERT ON WITHDRAWAL DATE MUST FAIL
  -- ==========================================================

  v_denied :=
    false;


  begin

    insert into public.lessons (
      student_id,
      teacher_id,
      branch_id,
      starts_at,
      duration_minutes,
      lesson_type,
      status
    )
    values (
      v_student_id,
      v_teacher_id,
      v_branch_id,
      (
        v_withdrawal_date + time '17:00'
      ) at time zone 'Asia/Seoul',
      30,
      'makeup'::public.lesson_type,
      'scheduled'::public.lesson_status
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_ON_OR_AFTER_WITHDRAWAL' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: table guard allowed withdrawal-date lesson insert';

  end if;


  -- ==========================================================
  -- 15. EXISTING PRE-WITHDRAWAL LESSON CANNOT BE MOVED
  --     TO AFTER WITHDRAWAL
  -- ==========================================================

  v_denied :=
    false;


  begin

    update public.lessons
    set starts_at =
        (
          v_after_date + time '16:00'
        ) at time zone 'Asia/Seoul'

    where id =
          v_existing_before_lesson_id;

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_ON_OR_AFTER_WITHDRAWAL' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: table guard allowed lesson move after withdrawal';

  end if;


  -- Failed move must leave original starts_at untouched.
  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_existing_before_lesson_id

      and l.starts_at =
          (
            v_before_date + time '15:00'
          ) at time zone 'Asia/Seoul'
  ) then

    raise exception
      'TEST_FAILED: failed move mutated historical lesson';

  end if;


  -- ==========================================================
  -- 16. EXISTING FUTURE LESSON MAY STILL BE CANCELED
  --
  -- Trigger intentionally ignores canceled state.
  -- ==========================================================

  update public.lessons
  set
    status =
      'canceled'::public.lesson_status,

    canceled_by =
      v_student_id,

    canceled_at =
      pg_catalog.now(),

    cancellation_reason =
      'withdrawal_guard_test'

  where id =
        v_existing_after_lesson_id;


  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_existing_after_lesson_id

      and l.status =
          'canceled'::public.lesson_status

      and l.canceled_at is not null
  ) then

    raise exception
      'TEST_FAILED: existing post-withdrawal lesson could not be canceled';

  end if;


  -- ==========================================================
  -- 17. WITHDRAWAL SCHEDULING DID NOT PREMATURELY DEACTIVATE
  -- ==========================================================

  if not exists (
    select 1

    from public.students s

    join public.profiles p
      on p.id = s.id

    where s.id =
          v_student_id

      and s.status =
          'active'::public.student_status

      and s.withdrawal_date =
          v_withdrawal_date

      and p.is_active =
          true
  ) then

    raise exception
      'TEST_FAILED: scheduled withdrawal prematurely deactivated student';

  end if;

end;
$$;


select
  'PASS: withdrawal booking guard / day-before availability+booking / withdrawal-date hidden+rejected / post-withdrawal hidden / table insert guard / move guard / existing future lesson preserved / future cancellation allowed'
  as test_result;

rollback;
