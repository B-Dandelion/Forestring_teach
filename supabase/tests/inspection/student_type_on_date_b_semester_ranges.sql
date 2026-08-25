-- B1. columns
select
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_schema,
  c.udt_name,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in (
    'semesters',
    'branch_semester_overrides'
  )
order by c.table_name, c.ordinal_position;

-- B2. constraints
select
  rel.relname as table_name,
  con.conname,
  con.contype,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class rel
  on rel.oid = con.conrelid
join pg_namespace nsp
  on nsp.oid = rel.relnamespace
where nsp.nspname = 'public'
  and rel.relname in (
    'semesters',
    'branch_semester_overrides'
  )
order by rel.relname, con.conname;

-- B3. indexes
select
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in (
    'semesters',
    'branch_semester_overrides'
  )
order by tablename, indexname;

-- B4. triggers + trigger function definitions
select
  rel.relname as table_name,
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
  and rel.relname in (
    'semesters',
    'branch_semester_overrides'
  )
  and not trg.tgisinternal
order by rel.relname, trg.tgname;
