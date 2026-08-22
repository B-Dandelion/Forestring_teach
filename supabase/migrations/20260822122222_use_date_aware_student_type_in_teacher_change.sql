do $migration$
declare
  v_function_oid oid;
  v_definition text;

  v_old_student_lock text := $old$
  select
    p.branch_id,
    s.status,
    s.student_type,
    s.withdrawal_date

  into
    v_student_branch_id,
    v_student_status,
    v_student_type,
    v_student_withdrawal_date
$old$;

  v_new_student_lock text := $new$
  select
    p.branch_id,
    s.status,
    s.withdrawal_date

  into
    v_student_branch_id,
    v_student_status,
    v_student_withdrawal_date
$new$;

  v_old_withdrawal_guard text := $old$
  if v_student_withdrawal_date is not null
     and p_effective_on >=
         v_student_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_CHANGE_AFTER_STUDENT_WITHDRAWAL';

  end if;
$old$;

  v_new_withdrawal_guard text := $new$
  if v_student_withdrawal_date is not null
     and p_effective_on >=
         v_student_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_CHANGE_AFTER_STUDENT_WITHDRAWAL';

  end if;


  -- Interpret the student's type at the teacher-change
  -- effective date.
  --
  -- Future semester plans must not mutate
  -- students.student_type before the semester transition.
  v_student_type :=
    private.student_type_on_date(
      p_student_id,
      p_effective_on
    );
$new$;

begin
  select p.oid
  into v_function_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'change_student_teacher'
    and pg_get_function_identity_arguments(p.oid) =
      'p_student_id uuid, p_teacher_id uuid, p_effective_on date';

  if v_function_oid is null then
    raise exception
      'FORESTRING_MIGRATION_CHANGE_STUDENT_TEACHER_NOT_FOUND';
  end if;


  v_definition :=
    pg_get_functiondef(v_function_oid);


  -- Safety:
  -- Do not silently patch an unexpected function definition.
  if strpos(
    v_definition,
    v_old_student_lock
  ) = 0 then
    raise exception
      'FORESTRING_MIGRATION_STUDENT_TYPE_LOCK_PATTERN_NOT_FOUND';
  end if;


  if strpos(
    v_definition,
    v_old_withdrawal_guard
  ) = 0 then
    raise exception
      'FORESTRING_MIGRATION_WITHDRAWAL_GUARD_PATTERN_NOT_FOUND';
  end if;


  v_definition :=
    replace(
      v_definition,
      v_old_student_lock,
      v_new_student_lock
    );


  v_definition :=
    replace(
      v_definition,
      v_old_withdrawal_guard,
      v_new_withdrawal_guard
    );


  execute v_definition;
end;
$migration$;