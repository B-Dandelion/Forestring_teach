do $migration$
declare
  v_target record;
  v_oid oid;
  v_definition text;

  v_begin_anchor text :=
    E'\nbegin\n';

  v_guard_block text :=
    E'\nbegin\n\n  if p_actor_id is not null then\n    perform private.require_effective_actor(\n      p_actor_id\n    );\n  end if;\n';
begin
  for v_target in
    select *
    from (
      values
        (
          'admin_create_manager_account_data'::text,
          'p_actor_id uuid, p_profile_id uuid, p_display_name text, p_login_name_normalized text, p_pin_hash text, p_pin_fingerprint text, p_branch_id uuid, p_work_hours jsonb'::text
        ),
        (
          'admin_create_student_account_data'::text,
          'p_actor_id uuid, p_profile_id uuid, p_display_name text, p_login_name_normalized text, p_pin_hash text, p_pin_fingerprint text, p_branch_id uuid, p_student_type student_type'::text
        ),
        (
          'admin_create_teacher_account_data'::text,
          'p_actor_id uuid, p_profile_id uuid, p_display_name text, p_login_name_normalized text, p_pin_hash text, p_pin_fingerprint text, p_branch_id uuid, p_work_hours jsonb'::text
        ),
        (
          'admin_get_account_pin_reset_context'::text,
          'p_actor_id uuid, p_profile_id uuid'::text
        ),
        (
          'admin_reset_account_pin_and_unlock_data'::text,
          'p_actor_id uuid, p_profile_id uuid, p_pin_hash text, p_pin_fingerprint text, p_expected_login_name_normalized text, p_rate_limit_subject_key text'::text
        ),
        (
          'admin_update_account_name_data'::text,
          'p_actor_id uuid, p_profile_id uuid, p_display_name text, p_login_name_normalized text'::text
        )
    ) as targets(
      function_name,
      identity_arguments
    )
  loop
    v_oid := null;

    select p.oid
    into v_oid
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname =
          v_target.function_name
      and pg_get_function_identity_arguments(
            p.oid
          ) =
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
      'private.require_effective_actor'
    ) > 0 then
      raise exception
        'FORESTRING_MIGRATION_EFFECTIVE_GUARD_ALREADY_PRESENT: %',
        v_target.function_name;
    end if;


    if strpos(
      v_definition,
      v_begin_anchor
    ) = 0 then
      raise exception
        'FORESTRING_MIGRATION_BEGIN_ANCHOR_NOT_FOUND: %',
        v_target.function_name;
    end if;


    -- regexp_replace without the "g" flag replaces only
    -- the first BEGIN, i.e. the outer PL/pgSQL body BEGIN.
    v_definition :=
      regexp_replace(
        v_definition,
        E'\nbegin\n',
        v_guard_block
      );


    execute v_definition;
  end loop;
end;
$migration$;
