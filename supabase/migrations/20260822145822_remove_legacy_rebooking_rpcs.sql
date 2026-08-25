drop function public.get_rebooking_options(uuid, date);

drop function public.rebook_lesson(
  uuid,
  timestamptz
);

drop function private.rebooking_slot_candidates(
  uuid,
  date,
  uuid
);
