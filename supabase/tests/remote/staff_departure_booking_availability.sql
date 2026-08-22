begin;

do $$
declare
  v_teacher_id uuid;
  v_student_id uuid;
  v_branch_id uuid;

  v_semester_id uuid;
  v_semester_code text;

  v_semester_start date;
  v_semester_end date;

  v_weekday smallint;
  v_selected_date date;

  v_starts_at timestamptz;

  v_right_id uuid;

  v_count integer;

  v_denied boolean;

  v_status_before
    public.lesson_right_status;

  v_status_after
    public.lesson_right_status;
begin

  -- ==========================================================
  -- 1. PICK ONLY STABLE IDENTITY FIXTURES
  --
  -- We intentionally DO NOT require:
  --   existing rights
  --   existing assignments
  --   existing bookable slots
  --
  -- Those are created below inside this transaction.
  -- ==========================================================

  select
    p.id,
    p.branch_id

  into
    v_teacher_id,
    v_branch_id

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.is_active = true

    and p.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

    and p.branch_id is not null

    and t.withdrawal_date is null

    -- Need at least one usable student in same branch.
    and exists (
      select 1

      from public.profiles sp

      join public.students s
        on s.id = sp.id

      where sp.branch_id =
            p.branch_id

        and sp.role =
            'student'::public.user_role

        and sp.is_active = true

        and s.status =
            'active'::public.student_status

        and s.withdrawal_date
            is null
    )

  order by
    p.created_at,
    p.id

  limit 1;


  if v_teacher_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active staff + active same-branch student';
  end if;


  select p.id
  into v_student_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.branch_id =
        v_branch_id

    and p.role =
        'student'::public.user_role

    and p.is_active = true

    and s.status =
        'active'::public.student_status

    and s.withdrawal_date
        is null

  order by
    p.created_at,
    p.id

  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active same-branch student';
  end if;


  -- ==========================================================
  -- 2. BUILD A FUTURE TEST WINDOW
  --
  -- Start after all known semester / closure / blocked /
  -- lesson dates, with 2199 as a minimum.
  --
  -- This prevents the test from colliding with operational
  -- scheduling data.
  -- ==========================================================

  select greatest(
    date '2199-01-01',

    coalesce(
      (
        select max(s.ends_on) + 30
        from public.semesters s
      ),
      date '2199-01-01'
    ),

    coalesce(
      (
        select max(cp.ends_on) + 30
        from public.closure_periods cp
      ),
      date '2199-01-01'
    ),

    coalesce(
      (
        select
          (
            max(bp.ends_at)
            at time zone 'Asia/Seoul'
          )::date
          + 30

        from public.blocked_periods bp
      ),
      date '2199-01-01'
    ),

    coalesce(
      (
        select
          (
            max(l.ends_at)
            at time zone 'Asia/Seoul'
          )::date
          + 30

        from public.lessons l
      ),
      date '2199-01-01'
    )
  )
  into v_semester_start;


  -- Exactly four whole weeks.
  v_semester_end :=
    v_semester_start + 27;


  v_semester_code :=
    '__FORESTRING_TEST_STAFF_DEPARTURE_' ||
    replace(
      gen_random_uuid()::text,
      '-',
      ''
    );


  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    v_semester_code,
    v_semester_start,
    v_semester_end
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 3. CHOOSE A WEEKDAY WITH NO EXISTING WORK-HOUR ROW
  --
  -- This guarantees our temporary segment cannot overlap
  -- another weekly segment for this teacher.
  -- ==========================================================

  select g.d::smallint
  into v_weekday

  from pg_catalog.generate_series(
    1,
    7
  ) as g(d)

  where not exists (
    select 1

    from public.teacher_work_hours wh

    where wh.teacher_id =
          v_teacher_id

      and wh.weekday =
          g.d
  )

  order by g.d

  limit 1;


  if v_weekday is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: teacher has work-hour rows on all 7 weekdays';
  end if;


  select gs::date
  into v_selected_date

  from pg_catalog.generate_series(
    v_semester_start::timestamp,
    v_semester_end::timestamp,
    interval '1 day'
  ) gs

  where extract(
          isodow
          from gs
        )::smallint =
        v_weekday

  order by gs

  limit 1;


  if v_selected_date is null then
    raise exception
      'TEST_FAILED: could not resolve selected test date';
  end if;


  v_starts_at :=
    (
      v_selected_date
      + time '10:00'
    )
    at time zone 'Asia/Seoul';


  -- ==========================================================
  -- 4. CREATE TEMPORARY WORK HOURS
  -- ==========================================================

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
  -- 5. CREATE TEMPORARY ASSIGNMENT
  --
  -- Same-branch identity is real.
  -- Scheduling relationship itself is synthetic.
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on,
    branch_id
  )
  values (
    v_teacher_id,
    v_student_id,
    v_semester_start,
    v_semester_end,
    v_branch_id
  );


  -- ==========================================================
  -- 6. CREATE TEMPORARY FLEX RIGHT
  --
  -- A flex_base right is enough to exercise the canonical
  -- availability + booking path without needing regular slots
  -- or lesson series.
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
    carryover_count
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
    15,

    'available'::public.lesson_right_status,
    0
  )
  returning id
  into v_right_id;


  select r.status
  into v_status_before

  from public.lesson_rights r

  where r.id =
        v_right_id;


  -- ==========================================================
  -- 7. BASELINE
  --
  -- No departure scheduled:
  -- 10:00 slot MUST exist.
  -- ==========================================================

  select count(*)::integer
  into v_count

  from private.lesson_right_slot_candidates(
    v_right_id,
    v_selected_date,
    v_student_id
  ) c

  where c.teacher_id =
        v_teacher_id

    and c.starts_at =
        v_starts_at;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: baseline synthetic slot unavailable; count=%',
      v_count;
  end if;


  -- ==========================================================
  -- 8. DAY BEFORE WITHDRAWAL IS STILL VALID
  --
  -- withdrawal_date is first NON-working day.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_selected_date + 1

  where id =
        v_teacher_id;


  select count(*)::integer
  into v_count

  from private.lesson_right_slot_candidates(
    v_right_id,
    v_selected_date,
    v_student_id
  ) c

  where c.teacher_id =
        v_teacher_id

    and c.starts_at =
        v_starts_at;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: day before teacher withdrawal was hidden; count=%',
      v_count;
  end if;


  -- ==========================================================
  -- 9. WITHDRAWAL DAY ITSELF IS NOT AVAILABLE
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_selected_date

  where id =
        v_teacher_id;


  select count(*)::integer
  into v_count

  from private.lesson_right_slot_candidates(
    v_right_id,
    v_selected_date,
    v_student_id
  ) c

  where c.starts_at =
        v_starts_at;


  if v_count <> 0 then
    raise exception
      'TEST_FAILED: withdrawal-day slot remained visible; count=%',
      v_count;
  end if;


  -- ==========================================================
  -- 10. STALE CLIENT BOOKING MUST ALSO FAIL
  --
  -- Imagine Flutter loaded v_starts_at BEFORE the departure
  -- was scheduled.
  --
  -- book_lesson_right() must re-check the authoritative
  -- candidate function and reject it.
  -- ==========================================================

  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );


  v_denied :=
    false;


  begin

    perform public.book_lesson_right(
      v_right_id,
      v_starts_at
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
      'TEST_FAILED: stale withdrawal-day booking was accepted';
  end if;


  -- ==========================================================
  -- 11. FAILED BOOKING MUST BE ATOMIC
  -- ==========================================================

  select r.status
  into v_status_after

  from public.lesson_rights r

  where r.id =
        v_right_id;


  if v_status_after
     is distinct from
     v_status_before then

    raise exception
      'TEST_FAILED: rejected booking mutated right status from % to %',
      v_status_before,
      v_status_after;
  end if;


  if exists (
    select 1

    from public.lessons l

    where l.lesson_right_id =
          v_right_id
  ) then

    raise exception
      'TEST_FAILED: rejected booking created a lesson';
  end if;

end;
$$;


select
  'PASS: deterministic teacher-withdrawal availability / day-before allowed / withdrawal-day hidden / stale booking rejected / atomic right preservation'
  as test_result;

rollback;
