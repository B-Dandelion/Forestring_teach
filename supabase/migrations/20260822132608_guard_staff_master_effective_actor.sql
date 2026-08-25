do $migration$
declare
  v_target record;
  v_oid oid;
  v_definition text;

  v_auth_anchor text :=
    E'        ''FORESTRING_AUTH_REQUIRED'';\n  end if;';

  v_auth_replacement text :=
    E'        ''FORESTRING_AUTH_REQUIRED'';\n  end if;\n\n\n  perform private.require_effective_actor(\n    v_actor_id\n  );';

  v_finalize_anchor text :=
    E'  v_actor_id :=\n    auth.uid();';

  v_finalize_replacement text :=
    E'  v_actor_id :=\n    auth.uid();\n\n\n  if v_actor_id is not null then\n    perform private.require_effective_actor(\n      v_actor_id\n    );\n  end if;';

  v_branch_anchor text :=
    E'begin\n\n  -- master only';

  v_branch_replacement text :=
    E'begin\n\n  if (select auth.uid()) is not null then\n    perform private.require_effective_actor(\n      (select auth.uid())\n    );\n  end if;\n\n  -- master only';
begin

  -- Functions that already have an explicit AUTH_REQUIRED block.
  for v_target in
    select *
    from (
      values
        (
          'cancel_staff_departure'::text,
          'p_staff_id uuid'::text
        ),
        (
          'schedule_staff_departure'::text,
          'p_staff_id uuid, p_withdrawal_date date'::text
        ),
        (
          'change_staff_role'::text,
          'p_staff_id uuid, p_new_role user_role'::text
        )
    ) as targets(function_name, identity_arguments)
  loop
    v_oid := null;

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
      'private.require_effective_actor'
    ) > 0 then
      raise exception
        'FORESTRING_MIGRATION_EFFECTIVE_GUARD_ALREADY_PRESENT: %',
        v_target.function_name;
    end if;

    if strpos(
      v_definition,
      v_auth_anchor
    ) = 0 then
      raise exception
        'FORESTRING_MIGRATION_AUTH_ANCHOR_NOT_FOUND: %',
        v_target.function_name;
    end if;

    execute replace(
      v_definition,
      v_auth_anchor,
      v_auth_replacement
    );
  end loop;


  -- finalize_staff_departure historically has no explicit
  -- AUTH_REQUIRED branch. Preserve anonymous-call behavior,
  -- while rejecting an authenticated but ineffective actor.
  select p.oid
  into v_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'finalize_staff_departure'
    and pg_get_function_identity_arguments(p.oid) =
        'p_staff_id uuid';

  if v_oid is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: finalize_staff_departure';
  end if;

  v_definition :=
    pg_get_functiondef(v_oid);

  if strpos(
    v_definition,
    'private.require_effective_actor'
  ) > 0 then
    raise exception
      'FORESTRING_MIGRATION_EFFECTIVE_GUARD_ALREADY_PRESENT: finalize_staff_departure';
  end if;

  if strpos(
    v_definition,
    v_finalize_anchor
  ) = 0 then
    raise exception
      'FORESTRING_MIGRATION_ACTOR_ANCHOR_NOT_FOUND: finalize_staff_departure';
  end if;

  execute replace(
    v_definition,
    v_finalize_anchor,
    v_finalize_replacement
  );


  -- create_branch historically reports MASTER_REQUIRED for
  -- anonymous callers. Keep that behavior, but apply the
  -- canonical guard whenever auth.uid() exists.
  select p.oid
  into v_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_branch'
    and pg_get_function_identity_arguments(p.oid) =
        'p_name text';

  if v_oid is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: create_branch';
  end if;

  v_definition :=
    pg_get_functiondef(v_oid);

  if strpos(
    v_definition,
    'private.require_effective_actor'
  ) > 0 then
    raise exception
      'FORESTRING_MIGRATION_EFFECTIVE_GUARD_ALREADY_PRESENT: create_branch';
  end if;

  if strpos(
    v_definition,
    v_branch_anchor
  ) = 0 then
    raise exception
      'FORESTRING_MIGRATION_AUTH_ANCHOR_NOT_FOUND: create_branch';
  end if;

  execute replace(
    v_definition,
    v_branch_anchor,
    v_branch_replacement
  );

end;
$migration$;
