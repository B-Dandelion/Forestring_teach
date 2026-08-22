do $migration$
declare
  v_target record;
  v_oid oid;
  v_definition text;

  v_anchor text :=
    E'\n\n\n  select p.role';

  v_replacement text :=
    E'\n\n\n  perform private.require_effective_actor(\n    v_actor_id\n  );\n\n\n  select p.role';
begin
  for v_target in
    select *
    from (
      values
        (
          'cancel_student_withdrawal'::text,
          'p_student_id uuid'::text
        ),
        (
          'finalize_student_withdrawal'::text,
          'p_student_id uuid'::text
        ),
        (
          'reactivate_student'::text,
          'p_student_id uuid'::text
        ),
        (
          'schedule_student_withdrawal'::text,
          'p_student_id uuid, p_withdrawal_date date'::text
        )
    ) as targets(function_name, identity_arguments)
  loop

    select p.oid
    into v_oid
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = v_target.function_name
      and pg_get_function_identity_arguments(p.oid) =
          v_target.identity_arguments;

    if v_oid is null then
      raise exception
        'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: % (%)',
        v_target.function_name,
        v_target.identity_arguments;
    end if;


    v_definition :=
      pg_get_functiondef(v_oid);


    if strpos(
      v_definition,
      'perform private.require_effective_actor'
    ) > 0 then
      raise exception
        'FORESTRING_MIGRATION_EFFECTIVE_GUARD_ALREADY_PRESENT: %',
        v_target.function_name;
    end if;


    if strpos(
      v_definition,
      v_anchor
    ) = 0 then
      raise exception
        'FORESTRING_MIGRATION_AUTH_ANCHOR_NOT_FOUND: %',
        v_target.function_name;
    end if;


    v_definition :=
      replace(
        v_definition,
        v_anchor,
        v_replacement
      );


    execute v_definition;

  end loop;
end;
$migration$;
