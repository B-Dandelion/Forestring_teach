begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_actor_id uuid;

  v_random_slot_id uuid :=
    gen_random_uuid();

begin

  -- ==========================================================
  -- Find an effective active normal teacher.
  -- ==========================================================

  select p.id
  into v_actor_id

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  where p.is_active = true

    and p.role =
        'teacher'::public.user_role

    and (
      t.withdrawal_date is null
      or t.withdrawal_date > v_today
    )

  order by
    p.created_at,
    p.id

  limit 1;


  if v_actor_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active normal teacher';
  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_actor_id::text,
    true
  );


  -- ==========================================================
  -- NORMAL TEACHER
  --
  -- Even when trying to keep themselves as the teacher,
  -- recurring schedule modification must be forbidden.
  -- The function must reject BEFORE looking up the random slot.
  -- ==========================================================

  begin

    perform public.change_regular_schedule(
      v_random_slot_id,
      v_actor_id,
      1,
      time '10:00',
      15,
      v_today
    );

    raise exception
      'TEST_FAILED: normal teacher changed recurring schedule';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- SAME ACCOUNT TEMPORARILY AS MANAGER
  --
  -- This transaction-only role change proves manager passes the
  -- role gate. With a random slot it should then reach ordinary
  -- SLOT_NOT_FOUND validation.
  -- ==========================================================

  update public.profiles

  set role =
      'manager'::public.user_role

  where id =
        v_actor_id;


  begin

    perform public.change_regular_schedule(
      v_random_slot_id,
      v_actor_id,
      1,
      time '10:00',
      15,
      v_today
    );

    raise exception
      'TEST_FAILED: random regular slot unexpectedly existed';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- STATIC POLICY CHECK
  -- ==========================================================

  if pg_catalog.pg_get_functiondef(
       'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'
         ::regprocedure
     )
     like
       '%''manager''::public.user_role,%''teacher''::public.user_role%' then

    raise exception
      'TEST_FAILED: teacher remains in recurring-schedule role gate';

  end if;

end;
$$;


select
  'PASS: recurring schedule changes are master/manager only / normal teacher denied / manager reaches ordinary validation'
  as test_result;

rollback;
