-- ============================================================
-- Forestring v3
-- Inspect canonical source for student type on an effective date.
--
-- Inspection only. No data changes.
-- ============================================================


-- ============================================================
-- 1. Functions directly involved in semester/type transitions
-- ============================================================

select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid)
    as arguments,
  pg_catalog.pg_get_functiondef(p.oid)
    as definition

from pg_catalog.pg_proc p

join pg_catalog.pg_namespace n
  on n.oid = p.pronamespace

where n.nspname in (
  'public',
  'private'
)

  -- Ordinary functions only.
  -- Avoid aggregates such as array_agg.
  and p.prokind = 'f'

  and (
    p.proname in (
      'change_student_teacher',
      'transition_student_semester',
      'activate_student_semester_plan'
    )

    or p.proname ilike '%student_type%'
  )

order by
  n.nspname,
  p.proname,
  pg_catalog.pg_get_function_identity_arguments(p.oid);



-- ============================================================
-- 2. Tables/columns that may contain semester-plan student type
-- ============================================================

select
  table_schema,
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable

from information_schema.columns

where table_schema in (
  'public',
  'private'
)

and (
  column_name = 'student_type'

  or table_name ilike '%semester%plan%'

  or table_name ilike '%student%semester%'
)

order by
  table_schema,
  table_name,
  ordinal_position;



-- ============================================================
-- 3. Ordinary functions whose definition references student_type
--
-- MATERIALIZED is intentional:
-- first isolate normal functions, THEN call pg_get_functiondef().
-- ============================================================

with candidate_functions as materialized (
  select
    p.oid,
    n.nspname as schema_name,
    p.proname as function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
      as arguments

  from pg_catalog.pg_proc p

  join pg_catalog.pg_namespace n
    on n.oid = p.pronamespace

  where n.nspname in (
    'public',
    'private'
  )

    and p.prokind = 'f'
),

definitions as materialized (
  select
    cf.schema_name,
    cf.function_name,
    cf.arguments,
    pg_catalog.pg_get_functiondef(cf.oid)
      as definition

  from candidate_functions cf
)

select
  schema_name,
  function_name,
  arguments,
  definition

from definitions

where definition ilike '%student_type%'

order by
  schema_name,
  function_name,
  arguments;
