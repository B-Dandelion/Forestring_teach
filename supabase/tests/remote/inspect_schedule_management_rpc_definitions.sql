select
  'assign_student_teacher'
    as function_name,

  pg_get_functiondef(
    'public.assign_student_teacher(uuid,uuid,date)'
      ::regprocedure
  ) as definition

union all

select
  'change_student_teacher',

  pg_get_functiondef(
    'public.change_student_teacher(uuid,uuid,date)'
      ::regprocedure
  )

union all

select
  'change_regular_schedule',

  pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'
      ::regprocedure
  )

union all

select
  'replace_teacher_work_hours',

  pg_get_functiondef(
    'public.replace_teacher_work_hours(uuid,jsonb)'
      ::regprocedure
  )

union all

select
  'upsert_teacher_blocked_period',

  pg_get_functiondef(
    'public.upsert_teacher_blocked_period(uuid,timestamptz,timestamptz,text,uuid)'
      ::regprocedure
  )

union all

select
  'delete_teacher_blocked_period',

  pg_get_functiondef(
    'public.delete_teacher_blocked_period(uuid)'
      ::regprocedure
  );
