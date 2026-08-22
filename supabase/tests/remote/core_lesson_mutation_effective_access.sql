begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_staff_id uuid;
  v_student_id uuid;

  v_random_id uuid :=
    gen_random_uuid();

  v_denied boolean;
begin

  -- ==========================================================
  -- STAFF FIXTURE
  -- Used for cancel_lesson / update_lesson_once.
  -- ==========================================================

  select p.id
  into v_staff_id

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.is_active = true

    and p.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

    and t.withdrawal_date is null

  order by
    p.created_at,
    p.id

  limit 1;


  if v_staff_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active staff';
  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_staff_id::text,
    true
  );


  -- ==========================================================
  -- STAFF: FUTURE DEPARTURE
  --
  -- Guard passes, therefore ordinary function validation should
  -- reach LESSON_NOT_FOUND for a random lesson UUID.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today + 1
  where id =
        v_staff_id;


  begin

    perform public.cancel_lesson(
      v_random_id,
      null
    );

    raise exception
      'TEST_FAILED: random lesson unexpectedly canceled';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_LESSON_NOT_FOUND' then
        raise;
      end if;

  end;


  begin

    perform public.update_lesson_once(
      v_random_id,
      pg_catalog.now() + interval '7 days',
      15,
      false,
      null
    );

    raise exception
      'TEST_FAILED: random lesson unexpectedly updated';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_LESSON_NOT_FOUND' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- STAFF: DEPARTURE EFFECTIVE TODAY
  --
  -- Must fail before touching the lesson.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today
  where id =
        v_staff_id;


  v_denied := false;

  begin

    perform public.cancel_lesson(
      v_random_id,
      null
    );

  exception
    when insufficient_privilege then

      if sqlerrm =
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: departed staff reached cancel_lesson';
  end if;


  v_denied := false;

  begin

    perform public.update_lesson_once(
      v_random_id,
      pg_catalog.now() + interval '7 days',
      15,
      false,
      null
    );

  exception
    when insufficient_privilege then

      if sqlerrm =
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: departed staff reached update_lesson_once';
  end if;


  -- ==========================================================
  -- STUDENT FIXTURE
  -- Used for book_lesson_right.
  -- ==========================================================

  select p.id
  into v_student_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.is_active = true

    and p.role =
        'student'::public.user_role

    and s.status =
        'active'::public.student_status

    and s.withdrawal_date is null

  order by
    p.created_at,
    p.id

  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active student';
  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );


  -- Future withdrawal: guard passes, then normal RIGHT_NOT_FOUND.
  update public.students
  set withdrawal_date =
      v_today + 1
  where id =
        v_student_id;


  begin

    perform public.book_lesson_right(
      v_random_id,
      pg_catalog.now() + interval '7 days'
    );

    raise exception
      'TEST_FAILED: random lesson right unexpectedly booked';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_LESSON_RIGHT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- Effective today: actor guard must reject first.
  update public.students
  set withdrawal_date =
      v_today
  where id =
        v_student_id;


  v_denied := false;

  begin

    perform public.book_lesson_right(
      v_random_id,
      pg_catalog.now() + interval '7 days'
    );

  exception
    when insufficient_privilege then

      if sqlerrm =
         'FORESTRING_EFFECTIVE_ACCESS_REQUIRED' then
        v_denied := true;
      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: withdrawn student reached book_lesson_right';
  end if;


  -- ==========================================================
  -- STATIC COVERAGE
  -- ==========================================================

  if pg_catalog.pg_get_functiondef(
       'public.book_lesson_right(uuid,timestamptz)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: book_lesson_right guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.cancel_lesson(uuid,text)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: cancel_lesson guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.update_lesson_once(uuid,timestamptz,integer,boolean,text)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: update_lesson_once guard missing';

  end if;

end;
$$;


select
  'PASS: core lesson mutation effective-access guards / future cutoff allowed / effective cutoff denied / ordinary validation preserved'
  as test_result;

rollback;
