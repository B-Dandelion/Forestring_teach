-- A1. columns
select
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_schema,
  c.udt_name,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'student_semester_plans'
order by c.ordinal_position;

-- A2. constraints
select
  con.conname,
  con.contype,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class rel
  on rel.oid = con.conrelid
join pg_namespace nsp
  on nsp.oid = rel.relnamespace
where nsp.nspname = 'public'
  and rel.relname = 'student_semester_plans'
order by con.conname;

-- A3. indexes
select
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'student_semester_plans'
order by indexname;

-- A4. enum labels used by this table
select
  t.typname as enum_type,
  e.enumsortorder,
  e.enumlabel
from pg_class c
join pg_namespace n
  on n.oid = c.relnamespace
join pg_attribute a
  on a.attrelid = c.oid
join pg_type t
  on t.oid = a.atttypid
join pg_enum e
  on e.enumtypid = t.oid
where n.nspname = 'public'
  and c.relname = 'student_semester_plans'
  and a.attnum > 0
  and not a.attisdropped
order by t.typname, e.enumsortorder;

-- A5. triggers + trigger function definitions
select
  trg.tgname as trigger_name,
  pg_get_triggerdef(trg.oid, true) as trigger_definition,
  pn.nspname as function_schema,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
from pg_trigger trg
join pg_class rel
  on rel.oid = trg.tgrelid
join pg_namespace rn
  on rn.oid = rel.relnamespace
join pg_proc p
  on p.oid = trg.tgfoid
join pg_namespace pn
  on pn.oid = p.pronamespace
where rn.nspname = 'public'
  and rel.relname = 'student_semester_plans'
  and not trg.tgisinternal
order by trg.tgname;
