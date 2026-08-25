do $test$
begin
  if to_regprocedure(
    'public.get_rebooking_options(uuid,date)'
  ) is not null then
    raise exception
      'TEST_FAIL legacy get_rebooking_options still exists';
  end if;

  if to_regprocedure(
    'public.rebook_lesson(uuid,timestamptz)'
  ) is not null then
    raise exception
      'TEST_FAIL legacy rebook_lesson still exists';
  end if;

  if to_regprocedure(
    'private.rebooking_slot_candidates(uuid,date,uuid)'
  ) is not null then
    raise exception
      'TEST_FAIL legacy rebooking_slot_candidates still exists';
  end if;
end;
$test$;
