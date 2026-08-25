begin;

do $test$
declare
  v_function_oid oid;

  v_branch_id uuid := gen_random_uuid();
  v_student_id uuid := gen_random_uuid();

  v_withdrawal_date date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date + 3;

  v_period_count integer;
  v_ends_on date;
  v_end_reason text;
begin
  -- ==========================================================
  -- FUNCTION SECURITY
  -- ==========================================================

  select p.oid
  into v_function_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname =
        'sync_student_enrollment_period'
    and pg_get_function_identity_arguments(
          p.oid
        ) = ''
    and p.prosecdef = true
    and coalesce(
          p.proconfig,
          array[]::text[]
        ) @> array['search_path=""'];

  if v_function_oid is null then
    raise exception
      'TEST_FAIL enrollment sync trigger function security shape invalid';
  end if;

  if has_function_privilege(
       'public',
       v_function_oid,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       v_function_oid,
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       v_function_oid,
       'EXECUTE'
     )
  then
    raise exception
      'TEST_FAIL enrollment sync trigger function is externally executable';
  end if;

  if not has_function_privilege(
    'service_role',
    v_function_oid,
    'EXECUTE'
  ) then
    raise exception
      'TEST_FAIL service_role cannot execute enrollment sync trigger function';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c
      on c.oid = t.tgrelid
    join pg_namespace n
      on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'public'
      and c.relname = 'students'
      and t.tgname =
          'students_sync_enrollment_period'
      and pg_get_triggerdef(
            t.oid,
            true
          ) ilike
          '%AFTER INSERT OR UPDATE OF status, withdrawal_date%'
      and pg_get_triggerdef(
            t.oid,
            true
          ) ilike
          '%EXECUTE FUNCTION sync_student_enrollment_period()%'
  ) then
    raise exception
      'TEST_FAIL students enrollment sync trigger missing or changed';
  end if;

  -- ==========================================================
  -- ROLLBACK FIXTURE
  -- ==========================================================

  insert into public.branches (
    id,
    name,
    is_active
  )
  values (
    v_branch_id,
    'ROLLBACK enrollment sync '
      || left(v_branch_id::text, 8),
    true
  );

  insert into auth.users (id)
  values (v_student_id);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values (
    v_student_id,
    'Rollback Enrollment Student',
    'student'::public.user_role,
    v_branch_id,
    true
  );

  insert into public.students (
    id,
    status,
    withdrawal_date,
    student_type
  )
  values (
    v_student_id,
    'active'::public.student_status,
    null,
    'regular'::public.student_type
  );

  select count(*)::integer
  into v_period_count
  from public.student_enrollment_periods ep
  where ep.student_id = v_student_id
    and ep.ends_on is null
    and ep.start_reason = 'initial';

  if v_period_count <> 1 then
    raise exception
      'TEST_FAIL expected one initial enrollment period, found %',
      v_period_count;
  end if;

  update public.students
  set withdrawal_date =
      v_withdrawal_date
  where id = v_student_id;

  select
    ep.ends_on,
    ep.end_reason
  into
    v_ends_on,
    v_end_reason
  from public.student_enrollment_periods ep
  where ep.student_id = v_student_id
  order by
    ep.starts_on desc,
    ep.created_at desc
  limit 1;

  if v_ends_on is distinct from
       (v_withdrawal_date - 1)
     or v_end_reason is distinct from
        'withdrawal_scheduled'
  then
    raise exception
      'TEST_FAIL withdrawal scheduling did not sync enrollment period: ends_on=%, reason=%',
      v_ends_on,
      v_end_reason;
  end if;

  update public.students
  set withdrawal_date = null
  where id = v_student_id;

  select
    ep.ends_on,
    ep.end_reason
  into
    v_ends_on,
    v_end_reason
  from public.student_enrollment_periods ep
  where ep.student_id = v_student_id
  order by
    ep.starts_on desc,
    ep.created_at desc
  limit 1;

  if v_ends_on is not null
     or v_end_reason is not null then
    raise exception
      'TEST_FAIL withdrawal cancellation did not reopen enrollment period: ends_on=%, reason=%',
      v_ends_on,
      v_end_reason;
  end if;
end;
$test$;

rollback;
