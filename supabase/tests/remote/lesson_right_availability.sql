begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;

  v_teacher_a_id uuid;
  v_teacher_b_id uuid;

  v_student_id uuid;
  v_other_student_id uuid;

  v_semester_id uuid;
  v_right_id uuid;

  v_semester_start date :=
    date '2099-09-07';

  v_semester_end date :=
    date '2099-10-04';

  v_date_a date :=
    date '2099-09-14';

  v_date_b date :=
    date '2099-09-21';

  v_test_weekday smallint;

  v_count integer;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. PRIMARY FIXTURE
  --
  -- Need:
  --   manager
  --   normal teacher in same branch
  --   one active student in same branch
  --
  -- teacher A = normal teacher
  -- teacher B = manager (every manager has teachers row)
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    teacher_profile.id,
    student_profile.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_a_id,
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
      'TEST_FIXTURE_REQUIRED: manager + teacher + active student in same branch';

  end if;


  v_teacher_b_id :=
    v_manager_id;


  -- ==========================================================
  -- 2. SECOND STUDENT ENTITY
  --
  -- We deliberately keep the two-student test.
  --
  -- The existing database does NOT need to already have
  -- two active students in the same branch.
  --
  -- We only need another real student entity. Inside this
  -- transaction it is temporarily normalized to:
  --
  --   active
  --   same test branch
  --
  -- Everything is restored by ROLLBACK.
  -- ==========================================================

  select p.id
  into v_other_student_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id <>
        v_student_id

  order by
    case
      when p.branch_id = v_branch_id
        then 0
      else 1
    end,

    p.created_at

  limit 1;


  if v_other_student_id is null then

    raise exception
      'TEST_FIXTURE_REQUIRED: second student entity';

  end if;


  -- Temporarily make the second student a valid same-branch
  -- active lesson participant.
  --
  -- No historical assignment/lesson rows are rewritten.
  -- This transaction is rolled back at the end.

  update public.profiles
  set
    branch_id =
      v_branch_id,

    is_active =
      true

  where id =
        v_other_student_id;


  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_other_student_id;


  -- ==========================================================
  -- 3. WEEKDAY
  --
  -- date A and date B are exactly seven days apart.
  -- ==========================================================

  v_test_weekday :=
    extract(
      isodow
      from v_date_a
    )::smallint;


  -- ==========================================================
  -- 4. ISOLATE TEST TEACHER AVAILABILITY
  --
  -- Transaction rollback restores original work hours and
  -- blocked periods.
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id in (
    v_teacher_a_id,
    v_teacher_b_id
  );


  delete from public.blocked_periods
  where teacher_id in (
    v_teacher_a_id,
    v_teacher_b_id
  );


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values
    (
      v_teacher_a_id,
      v_test_weekday,
      time '10:00',
      time '12:00'
    ),

    (
      v_teacher_b_id,
      v_test_weekday,
      time '10:00',
      time '12:00'
    );


  -- ==========================================================
  -- 5. TEST SEMESTER
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-AVAILABILITY-2099',
    v_semester_start,
    v_semester_end
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 6. ISOLATE PRIMARY STUDENT ASSIGNMENT HISTORY
  --
  -- Preserve everything through transaction rollback.
  --
  -- Before test semester:
  --   old assignment may remain.
  --
  -- During/after test semester:
  --   replaced temporarily with our two controlled versions.
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id =
        v_student_id

    and starts_on >=
        v_semester_start;


  update public.teacher_student_assignments
  set
    ends_on =
      v_semester_start - 1

  where student_id =
        v_student_id

    and starts_on <
        v_semester_start

    and (
      ends_on is null
      or ends_on >=
         v_semester_start
    );


  -- ==========================================================
  -- 7. TEACHER CHANGE INSIDE SEMESTER
  --
  -- 09/07 ~ 09/20 = teacher A
  -- 09/21 ~        = teacher B
  --
  -- The SAME right must resolve the teacher from the
  -- selected date.
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_a_id,
    v_student_id,
    v_semester_start,
    v_date_b - 1
  );


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_b_id,
    v_student_id,
    v_date_b,
    null
  );


  -- ==========================================================
  -- 8. AVAILABLE 30-MINUTE FLEX RIGHT
  --
  -- The right contains:
  --   student
  --   branch
  --   semester
  --   duration
  --
  -- It intentionally does NOT permanently own a teacher.
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
  into v_right_id;


  -- ==========================================================
  -- 9. LOGIN AS OWNER STUDENT
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
      'sub',
        v_student_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 10. BASE AVAILABILITY
  --
  -- Work hours:
  --   10:00 ~ 12:00
  --
  -- Right duration:
  --   30 minutes
  --
  -- Valid 15-minute candidate starts:
  --
  --   10:00
  --   10:15
  --   10:30
  --   10:45
  --   11:00
  --   11:15
  --   11:30
  --
  -- Exactly 7.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_a
  );


  if v_count <> 7 then

    raise exception
      'TEST_FAILED: expected 7 base candidates, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 11. RIGHT DURATION MUST CONTROL EVERY CANDIDATE
  -- ==========================================================

  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_a
    ) option_row

    where option_row.ends_at
          -
          option_row.starts_at
          <>
          interval '30 minutes'
  ) then

    raise exception
      'TEST_FAILED: candidate duration differs from lesson-right duration';

  end if;


  -- ==========================================================
  -- 12. EVERY START MUST BE ON THE 15-MINUTE GRID
  -- ==========================================================

  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_a
    ) option_row

    where mod(
      extract(
        minute
        from (
          option_row.starts_at
          at time zone 'Asia/Seoul'
        )
      )::integer,
      15
    ) <> 0
  ) then

    raise exception
      'TEST_FAILED: candidate outside 15-minute grid';

  end if;


  -- ==========================================================
  -- 13. DATE A MUST USE TEACHER A
  -- ==========================================================

  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_a
    ) option_row

    where option_row.teacher_id <>
          v_teacher_a_id
  ) then

    raise exception
      'TEST_FAILED: date A resolved wrong teacher';

  end if;


  -- ==========================================================
  -- 14. DATE B MUST USE TEACHER B
  --
  -- The lesson right itself has not changed.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_b
  );


  if v_count <> 7 then

    raise exception
      'TEST_FAILED: teacher B expected 7 candidates, got %',
      v_count;

  end if;


  if exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_b
    ) option_row

    where option_row.teacher_id <>
          v_teacher_b_id
  ) then

    raise exception
      'TEST_FAILED: assignment change did not resolve teacher B';

  end if;


  -- ==========================================================
  -- 15. BLOCKED PERIOD
  --
  -- Teacher A blocked:
  --   10:30 ~ 11:00
  --
  -- Overlapping candidates removed:
  --
  --   10:15 ~ 10:45
  --   10:30 ~ 11:00
  --   10:45 ~ 11:15
  --
  -- Remaining:
  --
  --   10:00
  --   11:00
  --   11:15
  --   11:30
  --
  -- Exactly 4.
  -- ==========================================================

  insert into public.blocked_periods (
    teacher_id,
    starts_at,
    ends_at,
    reason,
    created_by
  )
  values (
    v_teacher_a_id,

    (
      v_date_a
      + time '10:30'
    ) at time zone 'Asia/Seoul',

    (
      v_date_a
      + time '11:00'
    ) at time zone 'Asia/Seoul',

    'availability rollback test',

    v_manager_id
  );


  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_a
  );


  if v_count <> 4 then

    raise exception
      'TEST_FAILED: blocked period expected 4 candidates, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 16. TEACHER COLLISION WITH ANOTHER STUDENT
  --
  -- This is why we deliberately use TWO students.
  --
  -- Existing actual lesson:
  --
  --   student 2
  --   teacher A
  --   11:00 ~ 11:30
  --
  -- Primary student has no lesson there.
  --
  -- Therefore these candidates disappear ONLY because the
  -- teacher is occupied:
  --
  --   11:00
  --   11:15
  --
  -- Remaining:
  --
  --   10:00
  --   11:30
  --
  -- Exactly 2.
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
    v_other_student_id,
    v_teacher_a_id,

    (
      v_date_a
      + time '11:00'
    ) at time zone 'Asia/Seoul',

    30,

    'makeup'::public.lesson_type,

    'scheduled'::public.lesson_status
  );


  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_a
  );


  if v_count <> 2 then

    raise exception
      'TEST_FAILED: teacher collision expected 2 candidates, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 17. STUDENT COLLISION WITH A DIFFERENT TEACHER
  --
  -- Existing actual lesson:
  --
  --   primary student
  --   teacher B
  --   11:30 ~ 12:00
  --
  -- Availability for date A is still being calculated for
  -- teacher A.
  --
  -- Therefore teacher A is free at 11:30, but the STUDENT
  -- themselves are occupied.
  --
  -- Remaining after previous teacher collision:
  --
  --   10:00
  --   11:30
  --
  -- Student collision removes 11:30.
  --
  -- Exactly 1 remains: 10:00.
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
    v_teacher_b_id,

    (
      v_date_a
      + time '11:30'
    ) at time zone 'Asia/Seoul',

    30,

    'makeup'::public.lesson_type,

    'scheduled'::public.lesson_status
  );


  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_a
  );


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: student collision expected 1 candidate, got %',
      v_count;

  end if;


  if not exists (
    select 1

    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_a
    ) option_row

    where (
      option_row.starts_at
      at time zone 'Asia/Seoul'
    )::time = time '10:00'
  ) then

    raise exception
      'TEST_FAILED: expected only surviving candidate 10:00';

  end if;


  -- ==========================================================
  -- 18. ACADEMY CLOSURE
  --
  -- Student self-booking must return ZERO options on any
  -- academy closure date.
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
    v_semester_id,
    v_branch_id,
    v_date_a,
    v_date_a,
    'availability closure test',
    'ordinary'::public.closure_kind
  );


  select count(*)::integer
  into v_count

  from public.get_lesson_right_booking_options(
    v_right_id,
    v_date_a
  );


  if v_count <> 0 then

    raise exception
      'TEST_FAILED: academy closure should return zero candidates';

  end if;


  -- ==========================================================
  -- 19. DATE OUTSIDE USABLE SEMESTER = HARD ERROR
  -- ==========================================================

  v_denied :=
    false;


  begin

    perform *
    from public.get_lesson_right_booking_options(
      v_right_id,
      date '2099-10-05'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_BOOKING_DATE_OUTSIDE_USABLE_SEMESTER' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: outside-semester booking date was accepted';

  end if;


  -- ==========================================================
  -- 20. SECOND STUDENT MAY NOT INSPECT FIRST STUDENT'S RIGHT
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_other_student_id::text,
    true
  );


  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
        v_other_student_id::text,

      'role',
        'authenticated'
    )::text,
    true
  );


  v_denied :=
    false;


  begin

    perform *
    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_b
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_RIGHT_FORBIDDEN' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: second student inspected another student lesson right';

  end if;


  -- ==========================================================
  -- 21. MANAGER MAY NOT USE STUDENT AVAILABILITY RPC
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


  v_denied :=
    false;


  begin

    perform *
    from public.get_lesson_right_booking_options(
      v_right_id,
      v_date_b
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_ACTIVE_STUDENT_REQUIRED' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then

    raise exception
      'TEST_FAILED: manager used student availability RPC';

  end if;

end;
$$;


select
  'PASS: lesson-right availability / two students / 15m grid / right duration / effective teacher assignment / work hours / blocked / teacher collision / student collision / closure / ownership'
  as test_result;

rollback;
