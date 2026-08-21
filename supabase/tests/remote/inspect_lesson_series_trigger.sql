select
  pg_get_functiondef(
    'public.set_lesson_series_branch()'::regprocedure
  ) as function_definition;

select
  tgname,
  pg_get_triggerdef(oid, true) as trigger_definition
from pg_trigger
where tgrelid = 'public.lesson_series'::regclass
  and not tgisinternal
order by tgname;
