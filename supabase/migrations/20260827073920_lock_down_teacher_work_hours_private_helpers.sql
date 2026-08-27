revoke all
on function private.teacher_work_hours_for_date(uuid, date)
from public, anon, authenticated;

revoke all
on function private.teacher_is_within_work_hours(
  uuid,
  date,
  integer,
  time without time zone,
  time without time zone
)
from public, anon, authenticated;

revoke all
on function private.refresh_current_teacher_work_hours_snapshot()
from public, anon, authenticated;
