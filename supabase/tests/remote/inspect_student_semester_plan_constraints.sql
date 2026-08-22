select
  c.conname as constraint_name,
  pg_catalog.pg_get_constraintdef(
    c.oid,
    true
  ) as definition

from pg_catalog.pg_constraint c

where c.conrelid =
      'public.student_semester_plans'::regclass

order by
  c.contype,
  c.conname;


select
  indexname,
  indexdef

from pg_catalog.pg_indexes

where schemaname = 'public'
  and tablename = 'student_semester_plans'

order by indexname;
