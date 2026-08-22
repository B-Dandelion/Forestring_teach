begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_staff_id uuid;
  v_staff_original_role public.user_role;

  v_student_id uuid;

  v_random_id uuid :=
    gen_random_uuid();

  v_denied boolean;
begin

  -- ==========================================================
  -- STAFF ACTOR
  --
  -- Any active teacher/manager can be used.
  -- A teacher is temporarily promoted to manager inside this
  -- rollback-only transaction because these read RPCs require
  -- manager/master.
  -- ==========================================================

  select
    p.id,
    p.role

  into
    v_staff_id,
    v_staff_original_role

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
    case
      when p.role =
           'manager'::public.user_role
        then 0
      else 1
    end,
    p.created_at,
    p.id

  limit 1;


  if v_staff_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active staff';
  end if;


  if v_staff_original_role =
     'teacher'::public.user_role then

    update public.profiles
    set role =
        'manager'::public.user_role
    where id =
          v_staff_id;

  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_staff_id::text,
    true
  );


  -- ==========================================================
  -- FUTURE DEPARTURE:
  -- guard must PASS and normal function validation must run.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today + 1
  where id =
        v_staff_id;


  begin

    perform *
    from public.get_assignable_teachers_for_student(
      v_random_id
    );

    raise exception
      'TEST_FAILED: random student unexpectedly existed';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_STUDENT_NOT_FOUND' then
        raise;
      end if;

  end;


  begin

    perform public.get_staff_departure_blockers(
      v_random_id
    );

    raise exception
      'TEST_FAILED: random staff unexpectedly existed';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_STAFF_NOT_FOUND' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- DEPARTURE EFFECTIVE TODAY:
  -- same RPCs must now fail AT THE ACTOR GATE.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today
  where id =
        v_staff_id;


  v_denied := false;

  begin

    perform *
    from public.get_assignable_teachers_for_student(
      v_random_id
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
      'TEST_FAILED: departed manager reached assignable-teachers RPC';
  end if;


  v_denied := false;

  begin

    perform public.get_staff_departure_blockers(
      v_random_id
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
      'TEST_FAILED: departed manager reached departure-blocker RPC';
  end if;


  -- ==========================================================
  -- STUDENT ACTOR
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


  -- Tomorrow: actor guard passes, then normal RIGHT_NOT_FOUND.
  update public.students
  set withdrawal_date =
      v_today + 1
  where id =
        v_student_id;


  begin

    perform *
    from public.get_lesson_right_booking_options(
      v_random_id,
      v_today
    );

    raise exception
      'TEST_FAILED: random right unexpectedly existed';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_LESSON_RIGHT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- Today: actor gate must reject before right lookup.
  update public.students
  set withdrawal_date =
      v_today
  where id =
        v_student_id;


  v_denied := false;

  begin

    perform *
    from public.get_lesson_right_booking_options(
      v_random_id,
      v_today
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
      'TEST_FAILED: withdrawn student reached booking-options RPC';
  end if;


  -- ==========================================================
  -- STATIC COVERAGE
  -- Make sure all three maintained RPCs actually contain the
  -- canonical guard after this migration.
  -- ==========================================================

  if pg_get_functiondef(
       'public.get_assignable_teachers_for_student(uuid)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: assignable-teachers guard missing';

  end if;


  if pg_get_functiondef(
       'public.get_lesson_right_booking_options(uuid,date)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: booking-options guard missing';

  end if;


  if pg_get_functiondef(
       'public.get_staff_departure_blockers(uuid)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: departure-blockers guard missing';

  end if;

end;
$$;


select
  'PASS: maintained read RPC effective-access guards / future cutoff allowed / effective cutoff denied / normal validation preserved'
  as test_result;

rollback;
