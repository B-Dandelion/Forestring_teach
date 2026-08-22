-- ============================================================
-- Forestring v3
-- Regular recurring schedule changes are administrative.
--
-- Allowed:
--   master
--   manager
--
-- Normal teachers may still use the separate one-off lesson
-- mutation flow where permitted.
-- ============================================================

do $$
declare
  v_def text;

  v_old text :=
    E'  if v_actor_role not in (\n'
    || E'    ''master''::public.user_role,\n'
    || E'    ''manager''::public.user_role,\n'
    || E'    ''teacher''::public.user_role\n'
    || E'  ) then';

  v_new text :=
    E'  if v_actor_role not in (\n'
    || E'    ''master''::public.user_role,\n'
    || E'    ''manager''::public.user_role\n'
    || E'  ) then';

begin

  select pg_catalog.pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'
      ::regprocedure
  )
  into v_def;


  if v_def is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: change_regular_schedule';
  end if;


  -- We expect the effective-access hardening to already exist.
  if pg_catalog.strpos(
       v_def,
       'private.require_effective_actor'
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_EFFECTIVE_GUARD_MISSING: change_regular_schedule';
  end if;


  if pg_catalog.strpos(
       v_def,
       v_old
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_ROLE_MARKER_NOT_FOUND: change_regular_schedule';
  end if;


  v_def :=
    pg_catalog.replace(
      v_def,
      v_old,
      v_new
    );


  execute v_def;

end;
$$;
