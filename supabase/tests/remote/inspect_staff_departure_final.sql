with
column_info as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', table_name,
        'column', column_name,
        'dataType', data_type,
        'udtName', udt_name,
        'nullable', is_nullable,
        'default', column_default
      )
      order by table_name, ordinal_position
    ),
    '[]'::jsonb
  ) as value
  from information_schema.columns
  where table_schema = 'public'
    and table_name in (
      'profiles',
      'teachers',
      'teacher_student_assignments',
      'regular_schedule_slots',
      'lesson_series',
      'lessons'
    )
),

trigger_info as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table', c.relname,
        'trigger', t.tgname,
        'definition',
          pg_get_triggerdef(t.oid, true)
      )
      order by c.relname, t.tgname
    ),
    '[]'::jsonb
  ) as value
  from pg_trigger t
  join pg_class c
    on c.oid = t.tgrelid
  join pg_namespace n
    on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname in (
      'teachers',
      'teacher_student_assignments',
      'regular_schedule_slots',
      'lesson_series',
      'lessons'
    )
),

function_info as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'schema', n.nspname,
        'name', p.proname,
        'arguments',
          pg_get_function_identity_arguments(p.oid),
        'definition',
          pg_get_functiondef(p.oid)
      )
      order by n.nspname, p.proname
    ),
    '[]'::jsonb
  ) as value
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where
    (
      n.nspname = 'public'
      and p.proname in (
        'assign_student_teacher',
        'change_student_teacher',
        'get_assignable_teachers_for_student',
        'change_regular_schedule',
        'book_lesson_right',
        'update_lesson_once',
        'change_staff_role'
      )
    )
    or
    (
      n.nspname = 'private'
      and p.proname in (
        'lesson_right_slot_candidates'
      )
    )
)

select jsonb_pretty(
  jsonb_build_object(
    'columns',
      (select value from column_info),

    'triggers',
      (select value from trigger_info),

    'functions',
      (select value from function_info)
  )
) as staff_departure_preflight;
