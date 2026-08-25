alter function public.assert_lesson_before_student_withdrawal()
  security definer;

revoke all
on function public.assert_lesson_before_student_withdrawal()
from public, anon, authenticated;

grant execute
on function public.assert_lesson_before_student_withdrawal()
to service_role;
