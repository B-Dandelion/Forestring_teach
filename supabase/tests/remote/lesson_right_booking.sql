begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;

  v_student_a_id uuid;
  v_student_b_id uuid;

  v_semester_id uuid;

  v_right_a_id uuid;
  v_right_b_id uuid;

  v_lesson_a_id uuid;
  v_rebooked_lesson_id uuid;

  v_test_date date :=
    date '2099-11-09';

  v_weekday smallint;

  v_result jsonb;

  v_count integer;
  v_denied boolean;
  v_audit_count integer;
begin

  -- ==========================================================
  -- 1. PRIMARY FIXTURE
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
    v_student_a_id

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
      'TEST_FIXTURE_REQUIRED: manager + teacher + student';
  end if;


  -- ==========================================================
  -- 2. SECOND STUDENT
  --
  -- Keep the two-student competition test.
  --
  -- A second real student entity is temporarily normalized
  -- into this branch/active state inside the transaction.
  -- ROLLBACK restores everything.
  -- ==========================================================

  select p.id
  into v_student_b_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id <>
        v_student_a_id

  order by
    case
      when p.branch_id = v_branch_id then 0
      else 1
    end,
    p.created_at

  limit 1;


  if v_student_b_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: second student entity';
  end if;


  update public.profiles
  set
    branch_id = v_branch_id,
    is_active = true
  where id = v_student_b_id;


  update public.students
  set
    status =
      'active'::public.student_status,
    withdrawal_date = null
  where id = v_student_b_id;


  -- ==========================================================
  -- 3. TEST WEEKDAY
  -- ==========================================================

  v_weekday :=
    extract(
      isodow from v_test_date
    )::smallint;


  -- ==========================================================
  -- 4. CONTROL WORK HOURS / BLOCKS
  -- ==========================================================

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
    'TEST-BOOK-RIGHT-2099',
    date '2099-11-02',
    date '2099-11-29'
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 6. ISOLATE ASSIGNMENT HISTORY
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id in (
    v_student_a_id,
    v_student_b_id
  )
  and starts_on >=
      date '2099-11-02';


  update public.teacher_student_assignments
  set ends_on =
      date '2099-11-01'

  where student_id in (
    v_student_a_id,
    v_student_b_id
  )

  and starts_on <
      date '2099-11-02'

  and (
    ends_on is null
    or ends_on >=
       date '2099-11-02'
  );


  -- Both students share the same teacher.
  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values
    (
      v_teacher_id,
      v_student_a_id,
      date '2099-11-02',
      null
    ),
    (
      v_teacher_id,
      v_student_b_id,
      date '2099-11-02',
      null
    );


  -- ==========================================================
  -- 7. TWO AVAILABLE FLEX RIGHTS
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
    v_student_a_id,
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
  into v_right_a_id;


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
    v_student_b_id,
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
  into v_right_b_id;


  -- ==========================================================
  -- 8. STUDENT A LOGIN
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_a_id::text,
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
      'sub', v_student_a_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 9. INVALID NON-CANDIDATE START
  --
  -- 10:07 is not on the 15-minute grid.
  -- ==========================================================

  v_denied := false;

  begin

    perform public.book_lesson_right(
      v_right_a_id,
      (
        v_test_date + time '10:07'
      ) at time zone 'Asia/Seoul'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: non-grid booking start was accepted';
  end if;


  -- Right must remain available after failed booking.
  if not exists (
    select 1
    from public.lesson_rights r
    where r.id = v_right_a_id
      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: failed booking mutated right state';
  end if;


  -- ==========================================================
  -- 10. SUCCESSFUL INITIAL BOOKING
  --
  -- Student supplies only:
  --   right id
  --   starts_at
  --
  -- Teacher and duration must come from DB.
  -- ==========================================================

  v_result :=
    public.book_lesson_right(
      v_right_a_id,
      (
        v_test_date + time '10:00'
      ) at time zone 'Asia/Seoul'
    );


  v_lesson_a_id :=
    (v_result ->> 'lessonId')::uuid;


  if v_lesson_a_id is null then
    raise exception
      'TEST_FAILED: lesson id missing after booking';
  end if;


  if (v_result ->> 'reusedLesson')::boolean <> false then
    raise exception
      'TEST_FAILED: initial booking unexpectedly reused lesson';
  end if;


  if (v_result ->> 'durationMinutes')::integer <> 30 then
    raise exception
      'TEST_FAILED: booking did not use right duration';
  end if;


  if (v_result ->> 'teacherId')::uuid <>
     v_teacher_id then
    raise exception
      'TEST_FAILED: booking resolved wrong teacher';
  end if;


  -- ==========================================================
  -- 11. RIGHT MUST NOW BE RESERVED
  -- ==========================================================

  if not exists (
    select 1
    from public.lesson_rights r
    where r.id = v_right_a_id
      and r.status =
          'reserved'::public.lesson_right_status
      and r.reserved_at is not null
  ) then
    raise exception
      'TEST_FAILED: booked right not reserved';
  end if;


  -- ==========================================================
  -- 12. CANONICAL FLEX LESSON
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id = v_lesson_a_id

      and l.lesson_right_id =
          v_right_a_id

      and l.student_id =
          v_student_a_id

      and l.teacher_id =
          v_teacher_id

      and l.branch_id =
          v_branch_id

      and l.lesson_type =
          'flex'::public.lesson_type

      and l.status =
          'scheduled'::public.lesson_status

      and l.series_id is null

      and l.occurrence_at is null

      and l.duration_minutes = 30

      and l.starts_at =
          (
            v_test_date + time '10:00'
          ) at time zone 'Asia/Seoul'

      and l.ends_at =
          (
            v_test_date + time '10:30'
          ) at time zone 'Asia/Seoul'
  ) then
    raise exception
      'TEST_FAILED: canonical flex lesson state incorrect';
  end if;


  -- ==========================================================
  -- 13. SAME RIGHT MAY NOT BE BOOKED TWICE
  -- ==========================================================

  v_denied := false;

  begin

    perform public.book_lesson_right(
      v_right_a_id,
      (
        v_test_date + time '10:30'
      ) at time zone 'Asia/Seoul'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: reserved right was booked twice';
  end if;


  -- ==========================================================
  -- 14. SECOND STUDENT MAY NOT USE STUDENT A RIGHT
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_b_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_student_b_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;

  begin

    perform public.book_lesson_right(
      v_right_a_id,
      (
        v_test_date + time '10:30'
      ) at time zone 'Asia/Seoul'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_LESSON_RIGHT_FORBIDDEN' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: second student used another student right';
  end if;


  -- ==========================================================
  -- 15. SAME SLOT COMPETITION
  --
  -- Student A already owns teacher's 10:00~10:30.
  --
  -- Student B tries the same exact start with own valid right.
  --
  -- Candidate engine must reject it.
  -- ==========================================================

  v_denied := false;

  begin

    perform public.book_lesson_right(
      v_right_b_id,
      (
        v_test_date + time '10:00'
      ) at time zone 'Asia/Seoul'
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: second student booked occupied teacher slot';
  end if;


  -- Failed competing booking must not reserve student B right.
  if not exists (
    select 1
    from public.lesson_rights r
    where r.id = v_right_b_id
      and r.status =
          'available'::public.lesson_right_status
  ) then
    raise exception
      'TEST_FAILED: failed competing booking mutated second right';
  end if;


  -- ==========================================================
  -- 16. SIMULATE FLEX CANCELLATION STATE
  --
  -- The real cancellation RPC is the NEXT domain task.
  --
  -- For this booking test we directly create the exact state
  -- book_lesson_right() is designed to accept:
  --
  -- lesson = canceled
  -- same right = available
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_a_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_student_a_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  update public.lessons
  set
    status =
      'canceled'::public.lesson_status,

    canceled_by =
      v_student_a_id,

    canceled_at =
      pg_catalog.now(),

    cancellation_reason =
      'remote_booking_test'
  where id =
        v_lesson_a_id;


  update public.lesson_rights
  set
    status =
      'available'::public.lesson_right_status,

    reserved_at =
      null
  where id =
        v_right_a_id;


  -- ==========================================================
  -- 17. REBOOK SAME RIGHT
  --
  -- Must reuse the SAME lesson row instead of creating another.
  -- ==========================================================

  v_result :=
    public.book_lesson_right(
      v_right_a_id,
      (
        v_test_date + time '10:30'
      ) at time zone 'Asia/Seoul'
    );


  v_rebooked_lesson_id :=
    (v_result ->> 'lessonId')::uuid;


  if (v_result ->> 'reusedLesson')::boolean <> true then
    raise exception
      'TEST_FAILED: canceled flex lesson was not reused';
  end if;


  if v_rebooked_lesson_id <>
     v_lesson_a_id then
    raise exception
      'TEST_FAILED: flex rebooking changed lesson identity';
  end if;


  -- ==========================================================
  -- 18. REBOOKED STATE
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_a_id

      and l.lesson_right_id =
          v_right_a_id

      and l.status =
          'scheduled'::public.lesson_status

      and l.starts_at =
          (
            v_test_date + time '10:30'
          ) at time zone 'Asia/Seoul'

      and l.ends_at =
          (
            v_test_date + time '11:00'
          ) at time zone 'Asia/Seoul'

      and l.duration_minutes = 30

      and l.canceled_by is null
      and l.canceled_at is null
      and l.cancellation_reason is null
  ) then
    raise exception
      'TEST_FAILED: rebooked flex lesson state incorrect';
  end if;


  -- ==========================================================
  -- 19. EXACTLY ONE LESSON PER RIGHT
  -- ==========================================================

  select count(*)::integer
  into v_count
  from public.lessons l
  where l.lesson_right_id =
        v_right_a_id;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: expected one lesson row for flex right, got %',
      v_count;
  end if;


  -- ==========================================================
  -- 20. RIGHT RESERVED AGAIN
  -- ==========================================================

  if not exists (
    select 1
    from public.lesson_rights r
    where r.id =
          v_right_a_id

      and r.status =
          'reserved'::public.lesson_right_status

      and r.reserved_at is not null
  ) then
    raise exception
      'TEST_FAILED: rebooked right not reserved';
  end if;


  -- ==========================================================
  -- 21. AUDIT
  --
  -- Successful booking mutations:
  --   first booking
  --   rebooking
  --
  -- Failed attempts must not create booking audits.
  -- ==========================================================

  select count(*)::integer
  into v_audit_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_a_id

    and a.semester_id =
        v_semester_id

    and a.event_type =
        'LESSON_RIGHT_BOOKED'

    and a.details ->> 'rightId' =
        v_right_a_id::text;


  if v_audit_count <> 2 then
    raise exception
      'TEST_FAILED: expected 2 booking audit events, got %',
      v_audit_count;
  end if;


  if not exists (
    select 1
    from public.audit_events a

    where a.event_type =
          'LESSON_RIGHT_BOOKED'

      and a.details ->> 'rightId' =
          v_right_a_id::text

      and (
        a.details ->> 'reusedLesson'
      )::boolean = true

      and a.details ->> 'lessonId' =
          v_lesson_a_id::text
  ) then
    raise exception
      'TEST_FAILED: reused-lesson booking audit missing';
  end if;

end;
$$;


select
  'PASS: lesson-right booking / two students / server duration+teacher / occupied slot / ownership / right reservation / flex lesson creation / same-id rebooking / audit'
  as test_result;

rollback;
