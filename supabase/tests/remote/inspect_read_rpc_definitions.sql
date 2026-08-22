select
  'get_assignable_teachers_for_student'
    as function_name,

  pg_get_functiondef(
    'public.get_assignable_teachers_for_student(uuid)'
      ::regprocedure
  ) as definition

union all

select
  'get_lesson_right_booking_options',

  pg_get_functiondef(
    'public.get_lesson_right_booking_options(uuid,date)'
      ::regprocedure
  )

union all

select
  'get_staff_departure_blockers',

  pg_get_functiondef(
    'public.get_staff_departure_blockers(uuid)'
      ::regprocedure
  );
