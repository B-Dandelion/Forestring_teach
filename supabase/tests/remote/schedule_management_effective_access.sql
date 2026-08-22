begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_actor_id uuid;
  v_original_role public.user_role;

  v_random_id uuid :=
    gen_random_uuid();

  v_denied boolean;
begin

  -- ==========================================================
  -- ACTOR FIXTURE
  --
  -- Prefer manager.
  -- If only a teacher is available, temporarily promote inside
  -- this rollback-only transaction.
  -- ==========================================================

  select
    p.id,
    p.role

  into
    v_actor_id,
    v_original_role

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.is_active = true

    and p.branch_id is not null

    and p.role in (
      'manager'::public.user_role,
      'teacher'::public.user_role
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


  if v_actor_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active staff actor';
  end if;


  if v_original_role =
     'teacher'::public.user_role then

    update public.profiles
    set role =
        'manager'::public.user_role
    where id =
          v_actor_id;

  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_actor_id::text,
    true
  );


  -- ==========================================================
  -- FUTURE DEPARTURE
  --
  -- Effective-access guard must PASS.
  -- Each function should therefore reach its normal target
  -- validation instead.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today + 1
  where id =
        v_actor_id;


  -- assign_student_teacher
  begin

    perform public.assign_student_teacher(
      v_random_id,
      v_random_id,
      v_today
    );

    raise exception
      'TEST_FAILED: random student unexpectedly assigned';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_STUDENT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- change_student_teacher
  begin

    perform public.change_student_teacher(
      v_random_id,
      v_random_id,
      v_today
    );

    raise exception
      'TEST_FAILED: random student unexpectedly changed teacher';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_STUDENT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- change_regular_schedule
  begin

    perform public.change_regular_schedule(
      v_random_id,
      v_actor_id,
      1,
      time '10:00',
      15,
      v_today
    );

    raise exception
      'TEST_FAILED: random regular slot unexpectedly changed';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- replace_teacher_work_hours
  begin

    perform public.replace_teacher_work_hours(
      v_random_id,
      '[]'::jsonb
    );

    raise exception
      'TEST_FAILED: random teacher unexpectedly changed work hours';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_TEACHER_NOT_FOUND' then
        raise;
      end if;

  end;


  -- upsert_teacher_blocked_period
  begin

    perform public.upsert_teacher_blocked_period(
      v_random_id,
      pg_catalog.now() + interval '7 days',
      pg_catalog.now() + interval '7 days 1 hour',
      'test',
      null
    );

    raise exception
      'TEST_FAILED: random teacher unexpectedly received block';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_TEACHER_NOT_FOUND' then
        raise;
      end if;

  end;


  -- delete_teacher_blocked_period
  begin

    perform public.delete_teacher_blocked_period(
      v_random_id
    );

    raise exception
      'TEST_FAILED: random blocked period unexpectedly deleted';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_BLOCKED_PERIOD_NOT_FOUND' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- DEPARTURE EFFECTIVE TODAY
  --
  -- Every RPC must now stop at the actor gate BEFORE it can
  -- inspect or mutate the random target.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today
  where id =
        v_actor_id;


  -- ----------------------------------------------------------
  -- assign_student_teacher
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.assign_student_teacher(
      v_random_id,
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
      'TEST_FAILED: departed actor reached assign_student_teacher';
  end if;


  -- ----------------------------------------------------------
  -- change_student_teacher
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.change_student_teacher(
      v_random_id,
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
      'TEST_FAILED: departed actor reached change_student_teacher';
  end if;


  -- ----------------------------------------------------------
  -- change_regular_schedule
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.change_regular_schedule(
      v_random_id,
      v_actor_id,
      1,
      time '10:00',
      15,
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
      'TEST_FAILED: departed actor reached change_regular_schedule';
  end if;


  -- ----------------------------------------------------------
  -- replace_teacher_work_hours
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.replace_teacher_work_hours(
      v_random_id,
      '[]'::jsonb
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
      'TEST_FAILED: departed actor reached replace_teacher_work_hours';
  end if;


  -- ----------------------------------------------------------
  -- upsert_teacher_blocked_period
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.upsert_teacher_blocked_period(
      v_random_id,
      pg_catalog.now() + interval '7 days',
      pg_catalog.now() + interval '7 days 1 hour',
      'test',
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
      'TEST_FAILED: departed actor reached upsert_teacher_blocked_period';
  end if;


  -- ----------------------------------------------------------
  -- delete_teacher_blocked_period
  -- ----------------------------------------------------------

  v_denied := false;

  begin

    perform public.delete_teacher_blocked_period(
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
      'TEST_FAILED: departed actor reached delete_teacher_blocked_period';
  end if;


  -- ==========================================================
  -- STATIC COVERAGE
  -- ==========================================================

  if pg_catalog.pg_get_functiondef(
       'public.assign_student_teacher(uuid,uuid,date)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: assign_student_teacher guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.change_student_teacher(uuid,uuid,date)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: change_student_teacher guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: change_regular_schedule guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.replace_teacher_work_hours(uuid,jsonb)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: replace_teacher_work_hours guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.upsert_teacher_blocked_period(uuid,timestamptz,timestamptz,text,uuid)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: upsert_teacher_blocked_period guard missing';

  end if;


  if pg_catalog.pg_get_functiondef(
       'public.delete_teacher_blocked_period(uuid)'
         ::regprocedure
     ) not like
       '%private.require_effective_actor%' then

    raise exception
      'TEST_FAILED: delete_teacher_blocked_period guard missing';

  end if;

end;
$$;


select
  'PASS: schedule-management effective-access guards / future departure allowed / effective departure denied / ordinary validation preserved'
  as test_result;

rollback;
