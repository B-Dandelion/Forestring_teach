begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_student_type public.student_type;

  v_yesterday date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date - 1;

  v_before_lesson_count integer;
  v_before_assignment_count integer;
  v_before_series_count integer;
  v_before_slot_count integer;

  v_after_count integer;

  v_result jsonb;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. FIXTURE
  -- ==========================================================

  select
    mp.id,
    mp.branch_id,
    tp.id,
    sp.id,
    st.student_type

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id,
    v_student_id,
    v_student_type

  from public.profiles mp

  join public.teachers mt
    on mt.id =
       mp.id

  join public.profiles tp
    on tp.branch_id =
       mp.branch_id

   and tp.role =
       'teacher'::public.user_role

   and tp.is_active = true

  join public.teachers tt
    on tt.id =
       tp.id

  join public.profiles sp
    on sp.branch_id =
       mp.branch_id

   and sp.role =
       'student'::public.user_role

  join public.students st
    on st.id =
       sp.id

  where mp.role =
        'manager'::public.user_role

    and mp.is_active = true

    and mp.branch_id is not null

  order by
    mp.created_at,
    sp.created_at

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + student';
  end if;


  -- ==========================================================
  -- 2. SIMULATE CLEAN FINALIZED WITHDRAWAL STATE
  -- ==========================================================

  update public.lesson_rights
  set
    status =
      'revoked'::public.lesson_right_status,

    revoked_at =
      coalesce(
        revoked_at,
        pg_catalog.now()
      )

  where student_id =
        v_student_id

    and status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );


  update public.teacher_student_assignments
  set ends_on =
      least(
        coalesce(
          ends_on,
          v_yesterday
        ),
        v_yesterday
      )

  where student_id =
        v_student_id

    and starts_on <=
        v_yesterday

    and (
      ends_on is null
      or ends_on >
         v_yesterday
    );


  update public.students
  set
    status =
      'withdrawn'::public.student_status,

    withdrawal_date =
      v_yesterday

  where id =
        v_student_id;


  update public.profiles
  set
    is_active =
      false

  where id =
        v_student_id;


  -- ==========================================================
  -- 3. SNAPSHOT HISTORICAL COUNTS
  -- ==========================================================

  select count(*)::integer
  into v_before_lesson_count
  from public.lessons
  where student_id =
        v_student_id;


  select count(*)::integer
  into v_before_assignment_count
  from public.teacher_student_assignments
  where student_id =
        v_student_id;


  select count(*)::integer
  into v_before_series_count
  from public.lesson_series
  where student_id =
        v_student_id;


  select count(*)::integer
  into v_before_slot_count
  from public.regular_schedule_slots
  where student_id =
        v_student_id;


  -- ==========================================================
  -- 4. TEACHER CANNOT REACTIVATE
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
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
      'sub', v_teacher_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied :=
    false;


  begin

    perform public.reactivate_student(
      v_student_id
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_STUDENT_REACTIVATION_FORBIDDEN' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: teacher reactivated student';
  end if;


  -- ==========================================================
  -- 5. MANAGER REACTIVATES
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


  v_result :=
    public.reactivate_student(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: reactivation returned changed=false';

  end if;


  if (v_result ->> 'requiresEnrollmentSetup')::boolean <>
     true then

    raise exception
      'TEST_FAILED: enrollment setup flag missing';

  end if;


  -- ==========================================================
  -- 6. CURRENT STATE RESTORED
  -- ==========================================================

  if not exists (
    select 1

    from public.students s

    join public.profiles p
      on p.id =
         s.id

    where s.id =
          v_student_id

      and s.status =
          'active'::public.student_status

      and s.withdrawal_date is null

      and s.student_type =
          v_student_type

      and p.is_active =
          true

      and p.branch_id =
          v_branch_id
  ) then

    raise exception
      'TEST_FAILED: student/profile reactivation state incorrect';

  end if;


  -- ==========================================================
  -- 7. NOTHING HISTORICAL WAS RECREATED / DELETED
  -- ==========================================================

  select count(*)::integer
  into v_after_count
  from public.lessons
  where student_id =
        v_student_id;


  if v_after_count <>
     v_before_lesson_count then

    raise exception
      'TEST_FAILED: reactivation changed lesson count';

  end if;


  select count(*)::integer
  into v_after_count
  from public.teacher_student_assignments
  where student_id =
        v_student_id;


  if v_after_count <>
     v_before_assignment_count then

    raise exception
      'TEST_FAILED: reactivation changed assignment history';

  end if;


  select count(*)::integer
  into v_after_count
  from public.lesson_series
  where student_id =
        v_student_id;


  if v_after_count <>
     v_before_series_count then

    raise exception
      'TEST_FAILED: reactivation changed series history';

  end if;


  select count(*)::integer
  into v_after_count
  from public.regular_schedule_slots
  where student_id =
        v_student_id;


  if v_after_count <>
     v_before_slot_count then

    raise exception
      'TEST_FAILED: reactivation changed regular slot history';

  end if;


  -- No old entitlement may become usable again.
  if exists (
    select 1

    from public.lesson_rights r

    where r.student_id =
          v_student_id

      and r.status in (
        'available'::public.lesson_right_status,
        'reserved'::public.lesson_right_status
      )
  ) then

    raise exception
      'TEST_FAILED: reactivation revived old lesson right';

  end if;


  -- ==========================================================
  -- 8. AUDIT
  -- ==========================================================

  select count(*)::integer
  into v_after_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.event_type =
        'STUDENT_REACTIVATED';


  if v_after_count <> 1 then

    raise exception
      'TEST_FAILED: expected one reactivation audit, got %',
      v_after_count;

  end if;


  -- ==========================================================
  -- 9. SECOND CALL IDEMPOTENT
  -- ==========================================================

  v_result :=
    public.reactivate_student(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     false then

    raise exception
      'TEST_FAILED: repeated reactivation not idempotent';

  end if;


  select count(*)::integer
  into v_after_count

  from public.audit_events a

  where a.subject_profile_id =
        v_student_id

    and a.event_type =
        'STUDENT_REACTIVATED';


  if v_after_count <> 1 then

    raise exception
      'TEST_FAILED: idempotent call duplicated audit';

  end if;

end;
$$;


select
  'PASS: student reactivation / same UUID state restore / student type preserved / historical lessons+assignments+series+slots preserved / old rights not revived / authorization / audit / idempotency'
  as test_result;

rollback;
