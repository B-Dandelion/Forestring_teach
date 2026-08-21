begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_student_id uuid;

  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_date_1 date;
  v_date_2 date;

  v_result jsonb;
  v_count integer;
begin

  select
    mp.id,
    mp.branch_id,
    sp.id

  into
    v_manager_id,
    v_branch_id,
    v_student_id

  from public.profiles mp

  join public.profiles sp
    on sp.branch_id =
       mp.branch_id

   and sp.role =
       'student'::public.user_role

   and sp.is_active = true

  join public.students st
    on st.id =
       sp.id

   and st.status =
       'active'::public.student_status

  where mp.role =
        'manager'::public.user_role

    and mp.is_active = true

    and mp.branch_id is not null

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + active student';
  end if;


  update public.students
  set
    status =
      'active'::public.student_status,

    withdrawal_date =
      null

  where id =
        v_student_id;


  update public.profiles
  set is_active = true
  where id =
        v_student_id;


  v_date_1 :=
    v_today + 10;

  v_date_2 :=
    v_today + 20;


  -- ==========================================================
  -- Student cannot schedule own withdrawal.
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
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  begin

    perform public.schedule_student_withdrawal(
      v_student_id,
      v_date_1
    );

    raise exception
      'TEST_FAILED: student scheduled own withdrawal';

  exception
    when others then

      if sqlerrm <>
         'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- Manager
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
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
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- Past date rejected.
  begin

    perform public.schedule_student_withdrawal(
      v_student_id,
      v_today - 1
    );

    raise exception
      'TEST_FAILED: past withdrawal date accepted';

  exception
    when others then

      if sqlerrm <>
         'FORESTRING_STUDENT_WITHDRAWAL_DATE_IN_PAST' then
        raise;
      end if;

  end;


  -- First schedule.
  v_result :=
    public.schedule_student_withdrawal(
      v_student_id,
      v_date_1
    );


  if (v_result ->> 'changed')::boolean <>
     true then
    raise exception
      'TEST_FAILED: first schedule changed=false';
  end if;


  if not exists (
    select 1
    from public.students s
    where s.id = v_student_id
      and s.status =
          'active'::public.student_status
      and s.withdrawal_date =
          v_date_1
  ) then
    raise exception
      'TEST_FAILED: scheduled withdrawal not stored';
  end if;


  -- Same date is idempotent.
  v_result :=
    public.schedule_student_withdrawal(
      v_student_id,
      v_date_1
    );


  if (v_result ->> 'changed')::boolean <>
     false then
    raise exception
      'TEST_FAILED: same-date schedule not idempotent';
  end if;


  -- Change the planned date.
  v_result :=
    public.schedule_student_withdrawal(
      v_student_id,
      v_date_2
    );


  if (v_result ->> 'changed')::boolean <>
     true then
    raise exception
      'TEST_FAILED: withdrawal date change failed';
  end if;


  if not exists (
    select 1
    from public.students s
    where s.id = v_student_id
      and s.withdrawal_date =
          v_date_2
  ) then
    raise exception
      'TEST_FAILED: changed withdrawal date not stored';
  end if;


  -- Cancel before effective date.
  v_result :=
    public.cancel_student_withdrawal(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     true then
    raise exception
      'TEST_FAILED: withdrawal cancellation changed=false';
  end if;


  if exists (
    select 1
    from public.students s
    where s.id = v_student_id
      and s.withdrawal_date is not null
  ) then
    raise exception
      'TEST_FAILED: withdrawal date not cleared';
  end if;


  -- Cancel again -> idempotent.
  v_result :=
    public.cancel_student_withdrawal(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     false then
    raise exception
      'TEST_FAILED: repeated cancellation not idempotent';
  end if;


  -- Audit:
  -- schedule v1
  -- schedule date change
  -- cancellation
  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.event_type in (
      'STUDENT_WITHDRAWAL_SCHEDULED',
      'STUDENT_WITHDRAWAL_CANCELED'
    );


  if v_count < 3 then
    raise exception
      'TEST_FAILED: withdrawal scheduling audit missing';
  end if;

end;
$$;


select
  'PASS: student withdrawal scheduling / future date / date change / cancellation / authorization / idempotency / audit'
  as test_result;

rollback;
