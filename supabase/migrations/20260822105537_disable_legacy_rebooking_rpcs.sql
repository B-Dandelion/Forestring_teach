-- ============================================================
-- Forestring v3
-- Disable legacy rebooking Data API surface
--
-- Canonical replacement:
--   get_lesson_right_booking_options()
--   book_lesson_right()
--
-- Legacy storage/functions are NOT dropped yet.
-- They remain temporarily for historical cleanup compatibility.
-- ============================================================


-- ============================================================
-- 1. LEGACY READ API
-- ============================================================

revoke all
on function public.get_rebooking_options(
  uuid,
  date
)
from public, anon, authenticated;


-- Keep service_role temporarily until legacy dependency cleanup
-- is completed and verified.
grant execute
on function public.get_rebooking_options(
  uuid,
  date
)
to service_role;



-- ============================================================
-- 2. LEGACY BOOKING API
-- ============================================================

revoke all
on function public.rebook_lesson(
  uuid,
  timestamptz
)
from public, anon, authenticated;


grant execute
on function public.rebook_lesson(
  uuid,
  timestamptz
)
to service_role;