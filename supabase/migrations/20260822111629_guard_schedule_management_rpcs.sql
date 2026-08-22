-- ============================================================
-- Forestring v3
-- Effective-access guards for schedule-management RPCs
--
-- Only actor effective-access is changed here.
-- Existing business rules remain untouched.
-- ============================================================


-- ============================================================
-- 1. assign_student_teacher
-- ============================================================

do $$
declare
  v_def text;

  v_marker text :=
    E'  -- ==========================================================\n'
    || E'  -- ACTOR\n';
begin

  select pg_catalog.pg_get_functiondef(
    'public.assign_student_teacher(uuid,uuid,date)'
      ::regprocedure
  )
  into v_def;


  if pg_catalog.strpos(
       v_def,
       'private.require_effective_actor'
     ) > 0 then

    raise exception
      'FORESTRING_MIGRATION_GUARD_ALREADY_PRESENT: assign_student_teacher';

  end if;


  if pg_catalog.strpos(
       v_def,
       v_marker
     ) = 0 then

    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: assign_student_teacher';

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
-- 2. Remaining schedule-management RPCs
--
-- These all share the same actor-role lookup marker.
-- ============================================================

do $$
declare
  v_sig text;
  v_def text;

  v_marker text :=
    E'  select p.role\n'
    || E'  into v_actor_role';
begin

  foreach v_sig in array array[
    'public.change_student_teacher(uuid,uuid,date)',
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)',
    'public.replace_teacher_work_hours(uuid,jsonb)',
    'public.upsert_teacher_blocked_period(uuid,timestamptz,timestamptz,text,uuid)',
    'public.delete_teacher_blocked_period(uuid)'
  ]

  loop

    select pg_catalog.pg_get_functiondef(
      v_sig::regprocedure
    )
    into v_def;


    if v_def is null then

      raise exception
        'FORESTRING_MIGRATION_FUNCTION_NOT_FOUND: %',
        v_sig;

    end if;


    if pg_catalog.strpos(
         v_def,
         'private.require_effective_actor'
       ) > 0 then

      raise exception
        'FORESTRING_MIGRATION_GUARD_ALREADY_PRESENT: %',
        v_sig;

    end if;


    if pg_catalog.strpos(
         v_def,
         v_marker
       ) = 0 then

      raise exception
        'FORESTRING_MIGRATION_MARKER_NOT_FOUND: %',
        v_sig;

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

  end loop;

end;
$$;
