begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_staff_id uuid;
  v_master_id uuid;

  v_denied boolean;
begin

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


  -- active staff passes
  perform private.require_effective_actor(
    v_staff_id
  );


  -- future departure still passes
  update public.teachers
  set withdrawal_date =
      v_today + 1
  where id =
        v_staff_id;

  perform private.require_effective_actor(
    v_staff_id
  );


  -- effective departure day fails
  update public.teachers
  set withdrawal_date =
      v_today
  where id =
        v_staff_id;

  v_denied := false;

  begin

    perform private.require_effective_actor(
      v_staff_id
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
      'TEST_FAILED: departed staff passed actor guard';
  end if;


  -- null actor fails
  v_denied := false;

  begin

    perform private.require_effective_actor(
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
      'TEST_FAILED: null actor passed actor guard';
  end if;


  -- active master passes
  select p.id
  into v_master_id
  from public.profiles p
  where p.role =
        'master'::public.user_role
    and p.is_active = true
  order by
    p.created_at,
    p.id
  limit 1;

  if v_master_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master';
  end if;

  perform private.require_effective_actor(
    v_master_id
  );


  -- helper must not be externally executable
  if
    pg_catalog.has_function_privilege(
      'anon',
      'private.require_effective_actor(uuid)',
      'EXECUTE'
    )
    or
    pg_catalog.has_function_privilege(
      'authenticated',
      'private.require_effective_actor(uuid)',
      'EXECUTE'
    )
    or
    pg_catalog.has_function_privilege(
      'service_role',
      'private.require_effective_actor(uuid)',
      'EXECUTE'
    )
  then

    raise exception
      'TEST_FAILED: effective actor helper is externally executable';
  end if;

end;
$$;


select
  'PASS: effective actor guard / active allowed / future departure allowed / effective departure denied / null denied / master allowed / helper private'
  as test_result;

rollback;
