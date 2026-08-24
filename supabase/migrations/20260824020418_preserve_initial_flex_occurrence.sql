-- Preserve the first booked start time for standalone flex lessons.
--
-- A flex lesson has no recurring series, but occurrence_at is still useful as
-- its stable original appointment identity. Rebooking changes starts_at while
-- occurrence_at remains unchanged, so both student and staff history screens
-- can show the original time accurately.

create or replace function private.set_initial_flex_occurrence()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.lesson_type = 'flex'::public.lesson_type
     and new.lesson_right_id is not null
     and new.occurrence_at is null then
    new.occurrence_at := new.starts_at;
  end if;

  return new;
end;
$function$;

revoke all
on function private.set_initial_flex_occurrence()
from public, anon, authenticated;

drop trigger if exists
  lessons_set_initial_flex_occurrence
on public.lessons;

create trigger lessons_set_initial_flex_occurrence
before insert on public.lessons
for each row
execute function private.set_initial_flex_occurrence();

alter table public.lessons
drop constraint if exists
  lessons_type_series_check;

alter table public.lessons
add constraint lessons_type_series_check
check (
  (
    lesson_type = 'regular'::public.lesson_type
    and series_id is not null
    and occurrence_at is not null
  )
  or
  (
    lesson_type = 'flex'::public.lesson_type
    and series_id is null
    and occurrence_at is not null
  )
  or
  (
    lesson_type = 'makeup'::public.lesson_type
    and series_id is null
    and occurrence_at is null
  )
);

comment on function private.set_initial_flex_occurrence()
is
  'Preserves the initial booked start as the stable occurrence identity for flex lessons. Rebooking changes starts_at while occurrence_at remains unchanged.';

comment on constraint lessons_type_series_check
on public.lessons
is
  'Regular lessons require series and occurrence identity; flex lessons require standalone initial occurrence identity; makeup lessons remain standalone without occurrence identity.';
