-- ============================================================
-- Forestring v3
-- Effective-access guards for core lesson mutation RPCs
--
-- Narrow patch:
--   book_lesson_right
--   cancel_lesson
--   update_lesson_once
--
-- Existing business logic is preserved byte-for-byte as much
-- as possible. We inject only the canonical actor guard into
-- each current function definition.
-- ============================================================


-- ============================================================
-- 1. book_lesson_right
-- ============================================================

do $$
declare
  v_def text;

  v_marker text :=
    E'  select p.branch_id\n'
    || E'  into v_actor_branch_id';
begin

  select pg_catalog.pg_get_functiondef(
    'public.book_lesson_right(uuid,timestamptz)'
      ::regprocedure
  )
  into v_def;


  if v_def is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: book_lesson_right';
  end if;


  if v_def like
     '%private.require_effective_actor%' then

    raise exception
      'FORESTRING_MIGRATION_GUARD_ALREADY_PRESENT: book_lesson_right';

  end if;


  if pg_catalog.strpos(
       v_def,
       v_marker
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: book_lesson_right';

  end if;


  v_def :=
    pg_catalog.replace(
      v_def,

      v_marker,

      E'  perform private.require_effective_actor(\n'
      || E'    v_actor_id\n'
      || E'  );\n\n\n'
      || v_marker
    );


  execute v_def;

end;
$$;



-- ============================================================
-- 2. cancel_lesson
-- ============================================================

do $$
declare
  v_def text;

  v_marker text :=
    E'  select\n'
    || E'    p.role,\n'
    || E'    p.branch_id\n\n'
    || E'  into\n'
    || E'    v_actor_role,\n'
    || E'    v_actor_branch_id';
begin

  select pg_catalog.pg_get_functiondef(
    'public.cancel_lesson(uuid,text)'
      ::regprocedure
  )
  into v_def;


  if v_def is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: cancel_lesson';
  end if;


  if v_def like
     '%private.require_effective_actor%' then

    raise exception
      'FORESTRING_MIGRATION_GUARD_ALREADY_PRESENT: cancel_lesson';

  end if;


  if pg_catalog.strpos(
       v_def,
       v_marker
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: cancel_lesson';

  end if;


  v_def :=
    pg_catalog.replace(
      v_def,

      v_marker,

      E'  perform private.require_effective_actor(\n'
      || E'    v_actor_id\n'
      || E'  );\n\n\n'
      || v_marker
    );


  execute v_def;

end;
$$;



-- ============================================================
-- 3. update_lesson_once
-- ============================================================

do $$
declare
  v_def text;

  v_marker text :=
    E'  select p.role\n'
    || E'  into v_actor_role';
begin

  select pg_catalog.pg_get_functiondef(
    'public.update_lesson_once(uuid,timestamptz,integer,boolean,text)'
      ::regprocedure
  )
  into v_def;


  if v_def is null then
    raise exception
      'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: update_lesson_once';
  end if;


  if v_def like
     '%private.require_effective_actor%' then

    raise exception
      'FORESTRING_MIGRATION_GUARD_ALREADY_PRESENT: update_lesson_once';

  end if;


  if pg_catalog.strpos(
       v_def,
       v_marker
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: update_lesson_once';

  end if;


  v_def :=
    pg_catalog.replace(
      v_def,

      v_marker,

      E'  perform private.require_effective_actor(\n'
      || E'    v_actor_id\n'
      || E'  );\n\n\n'
      || v_marker
    );


  execute v_def;

end;
$$;
