begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_staff_id uuid;
  v_staff_name text;
  v_staff_fingerprint text;

  v_student_id uuid;
  v_student_name text;
  v_student_fingerprint text;

  v_lookup_active boolean;
begin

  -- ==========================================================
  -- STAFF FIXTURE
  -- ==========================================================

  select
    p.id,
    c.login_name_normalized,
    c.pin_fingerprint

  into
    v_staff_id,
    v_staff_name,
    v_staff_fingerprint

  from public.profiles p

  join public.teachers t
    on t.id = p.id

  join private.login_credentials c
    on c.profile_id = p.id

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
      'TEST_FIXTURE_REQUIRED: active staff credential';
  end if;


  -- ==========================================================
  -- STAFF: FUTURE DEPARTURE
  -- Still has access today.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today + 1
  where id =
        v_staff_id;


  if private.profile_has_effective_access(
       v_staff_id
     ) is distinct from true then

    raise exception
      'TEST_FAILED: staff lost access before withdrawal date';
  end if;


  select x.is_active
  into v_lookup_active

  from public.auth_lookup_login_credential(
    v_staff_name,
    v_staff_fingerprint
  ) x;


  if v_lookup_active
     is distinct from true then

    raise exception
      'TEST_FAILED: login blocked before staff withdrawal date';
  end if;


  -- Existing authenticated session should also still work.
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_staff_id::text,
    true
  );


  if private.is_active_user()
     is distinct from true then

    raise exception
      'TEST_FAILED: future-withdrawal staff RLS access blocked early';
  end if;


  -- ==========================================================
  -- STAFF: EFFECTIVE TODAY
  -- Login and existing-session RLS must both fail.
  -- ==========================================================

  update public.teachers
  set withdrawal_date =
      v_today
  where id =
        v_staff_id;


  if private.profile_has_effective_access(
       v_staff_id
     ) is distinct from false then

    raise exception
      'TEST_FAILED: withdrawal-day staff still effectively active';
  end if;


  select x.is_active
  into v_lookup_active

  from public.auth_lookup_login_credential(
    v_staff_name,
    v_staff_fingerprint
  ) x;


  if v_lookup_active
     is distinct from false then

    raise exception
      'TEST_FAILED: withdrawal-day staff login lookup remained active';
  end if;


  if private.is_active_user()
     is distinct from false then

    raise exception
      'TEST_FAILED: existing staff session remained RLS-active after withdrawal';
  end if;


  -- Raw administrative state intentionally remains true until
  -- lifecycle finalization.
  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_staff_id

      and p.is_active = true
  ) then

    raise exception
      'TEST_FAILED: effective-access check mutated profiles.is_active';
  end if;


  -- ==========================================================
  -- STUDENT FIXTURE
  --
  -- Same effective-access rule closes the equivalent stale
  -- session hole for scheduled student withdrawal.
  -- ==========================================================

  select
    p.id,
    c.login_name_normalized,
    c.pin_fingerprint

  into
    v_student_id,
    v_student_name,
    v_student_fingerprint

  from public.profiles p

  join public.students s
    on s.id = p.id

  join private.login_credentials c
    on c.profile_id = p.id

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
      'TEST_FIXTURE_REQUIRED: active student credential';
  end if;


  -- Tomorrow -> still active.
  update public.students
  set withdrawal_date =
      v_today + 1
  where id =
        v_student_id;


  if private.profile_has_effective_access(
       v_student_id
     ) is distinct from true then

    raise exception
      'TEST_FAILED: student lost access before withdrawal date';
  end if;


  -- Today -> access ends.
  update public.students
  set withdrawal_date =
      v_today
  where id =
        v_student_id;


  if private.profile_has_effective_access(
       v_student_id
     ) is distinct from false then

    raise exception
      'TEST_FAILED: withdrawal-day student still effectively active';
  end if;


  select x.is_active
  into v_lookup_active

  from public.auth_lookup_login_credential(
    v_student_name,
    v_student_fingerprint
  ) x;


  if v_lookup_active
     is distinct from false then

    raise exception
      'TEST_FAILED: withdrawal-day student login lookup remained active';
  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );


  if private.is_active_user()
     is distinct from false then

    raise exception
      'TEST_FAILED: existing student session remained RLS-active after withdrawal';
  end if;


  -- ==========================================================
  -- MASTER MUST REMAIN ACCESSIBLE
  -- ==========================================================

  if not exists (
    select 1

    from public.profiles p

    where p.role =
          'master'::public.user_role

      and p.is_active = true

      and private.profile_has_effective_access(
            p.id
          ) = true
  ) then

    raise exception
      'TEST_FAILED: active master lost effective access';
  end if;

end;
$$;


select
  'PASS: effective account access / future withdrawal allowed / effective-day login blocked / existing-session RLS blocked / student symmetry / raw profile state preserved'
  as test_result;

rollback;
