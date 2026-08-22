begin;

do $$
declare
  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

  v_start_on date :=
    v_today + 14;

  v_actor_id uuid;

  v_student_id uuid;
  v_student_branch_id uuid;

  v_teacher_id uuid;

  v_assignment_id uuid;
  v_saved_branch_id uuid;

begin

  -- ==========================================================
  -- 1. MASTER ACTOR
  -- ==========================================================

  select p.id
  into v_actor_id

  from public.profiles p

  where p.role =
        'master'::public.user_role

    and p.is_active = true

  order by
    p.created_at,
    p.id

  limit 1;


  if v_actor_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master';
  end if;


  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    v_actor_id::text,
    true
  );


  -- ==========================================================
  -- 2. ACTIVE STUDENT WITH AN ACTIVE TEACHER IN SAME BRANCH
  -- ==========================================================

  select
    s.id,
    p.branch_id

  into
    v_student_id,
    v_student_branch_id

  from public.students s

  join public.profiles p
    on p.id = s.id

  where p.is_active = true

    and p.role =
        'student'::public.user_role

    and p.branch_id is not null

    and s.status =
        'active'::public.student_status

    and s.withdrawal_date is null

    and exists (
      select 1

      from public.teachers t

      join public.profiles tp
        on tp.id = t.id

      where tp.branch_id =
            p.branch_id

        and tp.is_active = true

        and tp.role in (
          'teacher'::public.user_role,
          'manager'::public.user_role
        )

        and t.withdrawal_date is null
    )

  order by
    p.created_at,
    p.id

  limit 1;


  if v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active student + same-branch teacher';
  end if;


  select t.id
  into v_teacher_id

  from public.teachers t

  join public.profiles p
    on p.id = t.id

  where p.branch_id =
        v_student_branch_id

    and p.is_active = true

    and p.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

    and t.withdrawal_date is null

  order by
    p.created_at,
    p.id

  limit 1;


  if v_teacher_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: same-branch teacher';
  end if;


  -- ==========================================================
  -- 3. CREATE A CLEAN FUTURE WINDOW
  --
  -- Transaction-local only.
  -- Existing history before v_start_on is preserved.
  -- Any planned assignment on/after it is temporarily removed,
  -- and the assignment crossing the boundary is temporarily
  -- closed the day before.
  -- Everything rolls back at the end.
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id =
        v_student_id

    and starts_on >=
        v_start_on;


  update public.teacher_student_assignments

  set ends_on =
      v_start_on - 1

  where student_id =
        v_student_id

    and starts_on <
        v_start_on

    and (
      ends_on is null
      or ends_on >=
         v_start_on
    );


  -- ==========================================================
  -- 4. HAPPY PATH
  -- ==========================================================

  v_assignment_id :=
    public.assign_student_teacher(
      v_student_id,
      v_teacher_id,
      v_start_on
    );


  if v_assignment_id is null then
    raise exception
      'TEST_FAILED: assignment id was null';
  end if;


  select a.branch_id
  into v_saved_branch_id

  from public.teacher_student_assignments a

  where a.id =
        v_assignment_id

    and a.student_id =
        v_student_id

    and a.teacher_id =
        v_teacher_id

    and a.starts_on =
        v_start_on

    and a.ends_on is null;


  if not found then
    raise exception
      'TEST_FAILED: assignment row was not created correctly';
  end if;


  if v_saved_branch_id
     is distinct from
     v_student_branch_id then

    raise exception
      'TEST_FAILED: assignment branch was not derived correctly';
  end if;


  -- ==========================================================
  -- 5. OVERLAPPING ASSIGNMENT MUST FAIL
  -- ==========================================================

  begin

    perform public.assign_student_teacher(
      v_student_id,
      v_teacher_id,
      v_start_on
    );

    raise exception
      'TEST_FAILED: overlapping assignment was accepted';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_ASSIGNMENT_PERIOD_OVERLAP' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- 6. STUDENT WITHDRAWAL CUTOFF
  -- ==========================================================

  update public.students

  set withdrawal_date =
      v_start_on + 1

  where id =
        v_student_id;


  begin

    perform public.assign_student_teacher(
      v_student_id,
      v_teacher_id,
      v_start_on + 1
    );

    raise exception
      'TEST_FAILED: assignment allowed on student withdrawal date';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_ASSIGNMENT_AFTER_STUDENT_WITHDRAWAL' then
        raise;
      end if;

  end;


  update public.students

  set withdrawal_date =
      null

  where id =
        v_student_id;


  -- ==========================================================
  -- 7. TEACHER DEPARTURE CUTOFF
  -- ==========================================================

  update public.teachers

  set withdrawal_date =
      v_start_on + 1

  where id =
        v_teacher_id;


  begin

    perform public.assign_student_teacher(
      v_student_id,
      v_teacher_id,
      v_start_on + 1
    );

    raise exception
      'TEST_FAILED: assignment allowed on teacher departure date';

  exception
    when sqlstate 'P0001' then

      if sqlerrm <>
         'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL' then
        raise;
      end if;

  end;

end;
$$;


select
  'PASS: assign_student_teacher / successful assignment / branch derivation / overlap guard / student withdrawal cutoff / teacher departure cutoff'
  as test_result;

rollback;
