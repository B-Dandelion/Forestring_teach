begin;

do $$
begin

  -- Legacy APIs must no longer be callable by Flutter users.

  if pg_catalog.has_function_privilege(
       'authenticated',
       'public.get_rebooking_options(uuid,date)',
       'EXECUTE'
     ) then

    raise exception
      'TEST_FAILED: authenticated still executes legacy get_rebooking_options';

  end if;


  if pg_catalog.has_function_privilege(
       'authenticated',
       'public.rebook_lesson(uuid,timestamptz)',
       'EXECUTE'
     ) then

    raise exception
      'TEST_FAILED: authenticated still executes legacy rebook_lesson';

  end if;


  -- anon must also remain blocked.

  if pg_catalog.has_function_privilege(
       'anon',
       'public.get_rebooking_options(uuid,date)',
       'EXECUTE'
     )
     or
     pg_catalog.has_function_privilege(
       'anon',
       'public.rebook_lesson(uuid,timestamptz)',
       'EXECUTE'
     ) then

    raise exception
      'TEST_FAILED: anon can execute legacy rebooking API';

  end if;


  -- Do NOT physically delete the legacy system yet.
  -- finalize_student_withdrawal still contains compatibility
  -- handling for lesson_rebooking_credits.

  if to_regclass(
       'public.lesson_rebooking_credits'
     ) is null then

    raise exception
      'TEST_FAILED: legacy credits were destructively removed too early';

  end if;


  -- Canonical replacement APIs must stay available.

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.get_lesson_right_booking_options(uuid,date)',
       'EXECUTE'
     ) then

    raise exception
      'TEST_FAILED: canonical booking-options API lost permission';

  end if;


  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.book_lesson_right(uuid,timestamptz)',
       'EXECUTE'
     ) then

    raise exception
      'TEST_FAILED: canonical booking API lost permission';

  end if;

end;
$$;


select
  'PASS: legacy rebooking APIs blocked from Flutter / canonical lesson-right APIs preserved / legacy storage retained for staged cleanup'
  as test_result;

rollback;
