select
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default

from information_schema.columns

where table_schema = 'public'
  and table_name = 'student_semester_plans'

order by ordinal_position;
