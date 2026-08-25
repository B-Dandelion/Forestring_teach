revoke all
on function public.sync_student_enrollment_period()
from public, anon, authenticated;

grant execute
on function public.sync_student_enrollment_period()
to service_role;
