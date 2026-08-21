begin;

do $$
declare
  v_master_id uuid;
  v_staff_id uuid;
  v_branch_id uuid;

  v_original_role public.user_role;

  v_assignment_count integer;
  v_work_hour_count integer;
  v_lesson_count integer;

  v_after_count integer;

  v_result jsonb;
  v_denied boolean;
begin

  -- ==========================================================
  -- 1. MASTER
  -- ==========================================================

  select p.id
  into v_master_id

  from public.profiles p

  where p.role =
        'master'::public.user_role

    and p.is_active = true

  order by p.created_at

  limit 1;


  if v_master_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master';
  end if;


  -- ==========================================================
  -- 2. ACTIVE TEACHER/MANAGER
  -- ==========================================================

  select
    p.id,
    p.branch_id,
    p.role

  into
    v_staff_id,
    v_branch_id,
    v_original_role

  from public.profiles p

  join public.teachers t
    on t.id =
       p.id

  where p.role in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  )

    and p.is_active = true

    and p.branch_id is not null

  order by
    case
      when p.role =
           'teacher'::public.user_role
        then 0
      else 1
    end,
    p.created_at

  limit 1;


  if v_staff_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active teacher/manager';
  end if;


  -- ==========================================================
  -- 3. SNAPSHOT DATA THAT MUST NEVER CHANGE
  -- ==========================================================

  select count(*)::integer
  into v_assignment_count

  from public.teacher_student_assignments a

  where a.teacher_id =
        v_staff_id;


  select count(*)::integer
  into v_work_hour_count

  from public.teacher_work_hours w

  where w.teacher_id =
        v_staff_id;


  select count(*)::integer
  into v_lesson_count

  from public.lessons l

  where l.teacher_id =
        v_staff_id;


  -- ==========================================================
  -- 4. STAFF CANNOT PROMOTE THEMSELVES
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_staff_id::text,
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
      'sub', v_staff_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied :=
    false;


  begin

    perform public.change_staff_role(
      v_staff_id,

      case
        when v_original_role =
             'teacher'::public.user_role
          then 'manager'::public.user_role
        else 'teacher'::public.user_role
      end
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MASTER_REQUIRED' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: staff changed own role';
  end if;


  -- ==========================================================
  -- 5. MASTER LOGIN
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
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
      'sub', v_master_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 6. TEACHER -> MANAGER OR MANAGER -> TEACHER
  -- ==========================================================

  v_result :=
    public.change_staff_role(
      v_staff_id,

      case
        when v_original_role =
             'teacher'::public.user_role
          then 'manager'::public.user_role
        else 'teacher'::public.user_role
      end
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: first role change returned changed=false';

  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_staff_id

      and p.role =
          case
            when v_original_role =
                 'teacher'::public.user_role
              then 'manager'::public.user_role
            else 'teacher'::public.user_role
          end
  ) then

    raise exception
      'TEST_FAILED: profile role not changed';

  end if;


  -- Teacher entity MUST still exist.
  if not exists (
    select 1
    from public.teachers t
    where t.id =
          v_staff_id
  ) then

    raise exception
      'TEST_FAILED: teacher entity disappeared';

  end if;


  -- ==========================================================
  -- 7. OPERATIONAL DATA PRESERVED
  -- ==========================================================

  select count(*)::integer
  into v_after_count

  from public.teacher_student_assignments a

  where a.teacher_id =
        v_staff_id;


  if v_after_count <>
     v_assignment_count then
    raise exception
      'TEST_FAILED: role change mutated assignments';
  end if;


  select count(*)::integer
  into v_after_count

  from public.teacher_work_hours w

  where w.teacher_id =
        v_staff_id;


  if v_after_count <>
     v_work_hour_count then
    raise exception
      'TEST_FAILED: role change mutated work hours';
  end if;


  select count(*)::integer
  into v_after_count

  from public.lessons l

  where l.teacher_id =
        v_staff_id;


  if v_after_count <>
     v_lesson_count then
    raise exception
      'TEST_FAILED: role change mutated lessons';
  end if;


  -- ==========================================================
  -- 8. SAME ROLE -> IDEMPOTENT
  -- ==========================================================

  v_result :=
    public.change_staff_role(
      v_staff_id,

      (
        select p.role
        from public.profiles p
        where p.id = v_staff_id
      )
    );


  if (v_result ->> 'changed')::boolean <>
     false then

    raise exception
      'TEST_FAILED: same role was not idempotent';

  end if;


  -- ==========================================================
  -- 9. CHANGE BACK
  -- ==========================================================

  v_result :=
    public.change_staff_role(
      v_staff_id,
      v_original_role
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: reverse role change failed';

  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_staff_id

      and p.role =
          v_original_role

      and p.branch_id =
          v_branch_id
  ) then

    raise exception
      'TEST_FAILED: original role/branch not restored';
  end if;


  -- Two real changes -> exactly two audit rows created
  -- inside this rollback transaction.
  select count(*)::integer
  into v_after_count

  from public.audit_events a

  where a.subject_profile_id =
        v_staff_id

    and a.event_type =
        'STAFF_ROLE_CHANGED';


  if v_after_count < 2 then
    raise exception
      'TEST_FAILED: role-change audit missing';
  end if;


  -- ==========================================================
  -- 10. INVALID TARGET ROLE
  -- ==========================================================

  v_denied :=
    false;


  begin

    perform public.change_staff_role(
      v_staff_id,
      'student'::public.user_role
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_INVALID_STAFF_ROLE' then

        v_denied :=
          true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: staff converted to student';
  end if;

end;
$$;


select
  'PASS: staff teacher-manager role transition / same UUID / teacher entity preserved / branch preserved / assignments+work-hours+lessons untouched / master-only / idempotency / audit'
  as test_result;

rollback;
