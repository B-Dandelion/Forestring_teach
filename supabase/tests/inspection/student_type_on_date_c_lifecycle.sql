select
  n.nspname as function_schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname in ('public', 'private')
  and p.proname in (
    'activate_student_semester_plan',
    'transition_student_semester',
    'finalize_student_semester_rights',
    'change_student_teacher'
  )
order by p.proname, identity_arguments;
