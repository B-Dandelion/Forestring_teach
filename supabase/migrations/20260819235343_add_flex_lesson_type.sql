-- Flex bookings are normal lessons, not makeup lessons.

alter type public.lesson_type
add value if not exists 'flex'
after 'regular';