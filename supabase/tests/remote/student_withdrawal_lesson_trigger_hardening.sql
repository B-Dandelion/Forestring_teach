begin;

do $test$
declare
  v_function_oid oid;
  v_security_definer boolean;
  v_config text[];
  v_trigger_definition text;

  v_branch_id uuid := gen_random_uuid();
  v_teacher_id uuid := gen_random_uuid();
  v_student_id uuid := gen_random_uuid();

  v_withdrawal_date date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date + 2;

  v_before timestamptz;
  v_after timestamptz;

  v_message text;
begin
  select
    p.oid,
    p.prosecdef,
    p.proconfig
  into
    v_function_oid,
    v_security_definer,
    v_config
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname =
        'assert_lesson_before_student_withdrawal'
    and pg_get_function_identity_arguments(
          p.oid
        ) = '';

  if v_function_oid is null then
    raise exception
      'TEST_FAIL student withdrawal trigger function missing';
  end if;

  if v_security_definer is distinct from true then
    raise exception
      'TEST_FAIL student withdrawal trigger function is not SECURITY DEFINER';
  end if;

  if not (
    coalesce(v_config, array[]::text[])
    @> array['search_path=""']
  ) then
    raise exception
      'TEST_FAIL student withdrawal trigger function search_path is not empty: %',
      v_config;
  end if;

  if has_function_privilege(
       'public',
       v_function_oid,
       'EXECUTE'
     ) then
    raise exception
      'TEST_FAIL PUBLIC can execute student withdrawal trigger function';
  end if;

  if has_function_privilege(
       'anon',
       v_function_oid,
       'EXECUTE'
     ) then
    raise exception
      'TEST_FAIL anon can execute student withdrawal trigger function';
  end if;

  if has_function_privilege(
       'authenticated',
       v_function_oid,
       'EXECUTE'
     ) then
    raise exception
      'TEST_FAIL authenticated can execute student withdrawal trigger function';
  end if;

  if not has_function_privilege(
    'service_role',
    v_function_oid,
    'EXECUTE'
  ) then
    raise exception
      'TEST_FAIL service_role cannot execute student withdrawal trigger function';
  end if;

  select pg_get_triggerdef(
           t.oid,
           true
         )
  into v_trigger_definition
  from pg_trigger t
  join pg_class c
    on c.oid = t.tgrelid
  join pg_namespace n
    on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname = 'lessons'
    and t.tgname =
        'lessons_assert_student_withdrawal_boundary';

  if v_trigger_definition is null then
    raise exception
      'TEST_FAIL lessons student withdrawal trigger missing';
  end if;

  if v_trigger_definition not ilike
     '%BEFORE INSERT OR UPDATE OF student_id, starts_at, status%EXECUTE FUNCTION assert_lesson_before_student_withdrawal()%'
  then
    raise exception
      'TEST_FAIL unexpected student withdrawal trigger definition: %',
      v_trigger_definition;
  end if;

  v_before :=
    (
      (
        (v_withdrawal_date - 1)::timestamp
        + time '12:00'
      )
      at time zone 'Asia/Seoul'
    );

  v_after :=
    (
      (
        v_withdrawal_date::timestamp
        + time '10:00'
      )
      at time zone 'Asia/Seoul'
    );

  insert into public.branches (
    id,
    name,
    is_active
  )
  values (
    v_branch_id,
    'ROLLBACK student withdrawal trigger '
      || left(v_branch_id::text, 8),
    true
  );

  insert into auth.users (id)
  values
    (v_teacher_id),
    (v_student_id);

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active
  )
  values
    (
      v_teacher_id,
      'Rollback Teacher',
      'teacher'::public.user_role,
      v_branch_id,
      true
    ),
    (
      v_student_id,
      'Rollback Student',
      'student'::public.user_role,
      v_branch_id,
      true
    );

  insert into public.teachers (
    id,
    withdrawal_date
  )
  values (
    v_teacher_id,
    null
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
    v_withdrawal_date,
    'regular'::public.student_type
  );

  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    ends_at,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    v_before,
    30,
    v_before + interval '30 minutes',
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  );

  begin
    insert into public.lessons (
      student_id,
      teacher_id,
      starts_at,
      duration_minutes,
      ends_at,
      lesson_type,
      status
    )
    values (
      v_student_id,
      v_teacher_id,
      v_after,
      30,
      v_after + interval '30 minutes',
      'makeup'::public.lesson_type,
      'scheduled'::public.lesson_status
    );

    raise exception
      'TEST_FAIL scheduled lesson allowed on/after withdrawal';

  exception
    when others then
      get stacked diagnostics
        v_message = message_text;

      if v_message =
         'TEST_FAIL scheduled lesson allowed on/after withdrawal'
      then
        raise;
      end if;

      if v_message <>
         'FORESTRING_LESSON_ON_OR_AFTER_WITHDRAWAL'
      then
        raise exception
          'TEST_FAIL unexpected withdrawal boundary error: %',
          v_message;
      end if;
  end;

  insert into public.lessons (
    student_id,
    teacher_id,
    starts_at,
    duration_minutes,
    ends_at,
    lesson_type,
    status,
    canceled_at
  )
  values (
    v_student_id,
    v_teacher_id,
    v_after,
    30,
    v_after + interval '30 minutes',
    'makeup'::public.lesson_type,
    'canceled'::public.lesson_status,
    pg_catalog.now()
  );
end;
$test$;

rollback;
