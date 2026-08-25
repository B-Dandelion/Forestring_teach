begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_semester_id uuid;

  v_assignment_id uuid;
  v_future_assignment_id uuid;

  v_slot_a uuid;
  v_slot_b uuid;
  v_slot_c uuid;
  v_future_slot uuid;

  v_series_a uuid;
  v_series_b uuid;
  v_series_c uuid;
  v_future_series uuid;

  v_right_1 uuid;
  v_right_2 uuid;
  v_right_3 uuid;
  v_right_4 uuid;
  v_right_5 uuid;
  v_right_6 uuid;

  v_lesson_past uuid;
  v_lesson_past_2 uuid;
  v_lesson_moved_before uuid;
  v_lesson_moved_after uuid;
  v_lesson_boundary uuid;
  v_lesson_canceled_future uuid;

  v_cancellation_event_id uuid;
  v_legacy_credit_id uuid;

  v_result jsonb;
  v_count integer;

  v_today date :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;

begin

  -- ==========================================================
  -- 1. FIXTURE
  -- ==========================================================

  select
    mp.id,
    mp.branch_id,
    tp.id,
    sp.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id,
    v_student_id

  from public.profiles mp

  join public.teachers mt
    on mt.id =
       mp.id

  join public.profiles tp
    on tp.branch_id =
       mp.branch_id

   and tp.role =
       'teacher'::public.user_role

   and tp.is_active = true

  join public.teachers tt
    on tt.id =
       tp.id

  join public.profiles sp
    on sp.branch_id =
       mp.branch_id

   and sp.role =
       'student'::public.user_role

   and sp.is_active = true

  join public.students st
    on st.id =
       sp.id

  where mp.role =
        'manager'::public.user_role

    and mp.is_active = true

    and mp.branch_id is not null

  order by
    mp.created_at,
    tp.created_at,
    sp.created_at

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + active student';
  end if;


  update public.profiles
  set
    branch_id =
      v_branch_id,

    is_active =
      true

  where id =
        v_student_id;


  update public.students
  set
    status =
      'active'::public.student_status,

    student_type =
      'regular'::public.student_type,

    withdrawal_date =
      null

  where id =
        v_student_id;


  -- ==========================================================
  -- SYNTHETIC ENROLLMENT HISTORY
  --
  -- This withdrawal test deliberately uses 2004 dates.
  -- Enrollment periods are now authoritative history, so the
  -- fixture also needs an enrollment period covering 2004.
  --
  -- BEGIN / ROLLBACK keeps hosted data unchanged.
  -- ==========================================================

  delete from public.student_enrollment_periods ep
  where ep.student_id =
        v_student_id;


  insert into public.student_enrollment_periods (
    student_id,
    branch_id,
    starts_on,
    ends_on,
    started_by,
    start_reason
  )
  values (
    v_student_id,
    v_branch_id,
    date '2004-06-01',
    null,
    v_manager_id,
    'test_fixture'
  );


  -- Remove any accidental fixture data in the synthetic window.
  delete from public.teacher_student_assignments a
  where a.student_id =
        v_student_id

    and a.starts_on <=
        date '2004-07-31'

    and coalesce(
          a.ends_on,
          date '9999-12-31'
        ) >=
        date '2004-06-01';


  -- ==========================================================
  -- 2. SYNTHETIC SEMESTER
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-WITHDRAWAL-JUNE-2004',
    date '2004-06-01',
    date '2004-06-28'
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 3. ASSIGNMENT HISTORY
  --
  -- Current-at-withdrawal assignment -> close 6/14
  -- Pure future assignment -> delete
  -- ==========================================================

  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_id,
    v_student_id,
    date '2004-06-01',
    date '2004-06-30'
  )
  returning id
  into v_assignment_id;


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_id,
    v_student_id,
    date '2004-07-01',
    date '2004-07-31'
  )
  returning id
  into v_future_assignment_id;


  -- ==========================================================
  -- 4. REGULAR SLOT A
  --
  -- Monday series containing:
  --
  -- 6/07 -> normal past, preserve
  -- 6/14 -> normal past, preserve
  -- occurrence 6/21 -> actual moved to 6/14, preserve
  -- occurrence 6/28 -> actual moved to 6/20, delete
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2004-06-01',
    v_manager_id
  )
  returning id
  into v_slot_a;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2004-06-01',
    v_branch_id,
    v_slot_a
  )
  returning id
  into v_series_a;


  -- ==========================================================
  -- 5. SLOT B
  --
  -- Tuesday 6/15 = withdrawal boundary -> delete
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2004-06-01',
    v_manager_id
  )
  returning id
  into v_slot_b;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    2,
    time '19:00',
    30,
    date '2004-06-01',
    v_branch_id,
    v_slot_b
  )
  returning id
  into v_series_b;


  -- ==========================================================
  -- 6. SLOT C
  --
  -- Future canceled lesson + immutable cancellation ledger.
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2004-06-01',
    v_manager_id
  )
  returning id
  into v_slot_c;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    3,
    time '20:00',
    30,
    date '2004-06-01',
    v_branch_id,
    v_slot_c
  )
  returning id
  into v_series_c;


  -- ==========================================================
  -- 7. PURE FUTURE REGULAR CONFIG
  --
  -- Series should disappear.
  -- Slot remains bounded/tombstoned because slot rows are
  -- historical logical identities.
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2004-07-01',
    v_manager_id
  )
  returning id
  into v_future_slot;


  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    4,
    time '17:00',
    30,
    date '2004-07-01',
    v_branch_id,
    v_future_slot
  )
  returning id
  into v_future_series;


  -- ==========================================================
  -- 8. RIGHTS
  -- ==========================================================

  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_a,
    'regular_base'::public.lesson_right_origin,
    1,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2004-06-01 09:00:00+09'
  )
  returning id
  into v_right_1;


  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_a,
    'regular_base'::public.lesson_right_origin,
    2,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2004-06-01 09:00:00+09'
  )
  returning id
  into v_right_2;


  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_a,
    'regular_base'::public.lesson_right_origin,
    3,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2004-06-01 09:00:00+09'
  )
  returning id
  into v_right_3;


  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_a,
    'regular_base'::public.lesson_right_origin,
    4,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2004-06-01 09:00:00+09'
  )
  returning id
  into v_right_4;


  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_b,
    'regular_base'::public.lesson_right_origin,
    1,
    30,
    'reserved'::public.lesson_right_status,
    v_manager_id,
    timestamptz '2004-06-01 09:00:00+09'
  )
  returning id
  into v_right_5;


  -- Canceled lesson's entitlement has already been restored.
  insert into public.lesson_rights (
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    v_semester_id,
    v_semester_id,
    v_slot_c,
    'regular_base'::public.lesson_right_origin,
    1,
    30,
    'available'::public.lesson_right_status,
    v_manager_id
  )
  returning id
  into v_right_6;


  -- ==========================================================
  -- 9. ACTUAL LESSONS
  -- ==========================================================

  -- Normal past.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values (
    v_series_a,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-07 18:00:00+09',
    timestamptz '2004-06-07 18:00:00+09',
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_1
  )
  returning id
  into v_lesson_past;


  -- Another normal past.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values (
    v_series_a,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-14 18:00:00+09',
    timestamptz '2004-06-14 18:00:00+09',
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_2
  )
  returning id
  into v_lesson_past_2;


  -- Original occurrence AFTER withdrawal,
  -- but actual lesson moved BEFORE withdrawal.
  --
  -- MUST SURVIVE.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    rescheduled_by
  )
  values (
    v_series_a,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-21 18:00:00+09',
    timestamptz '2004-06-14 19:00:00+09',
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_3,
    v_manager_id
  )
  returning id
  into v_lesson_moved_before;


  -- Original occurrence before/around normal schedule,
  -- but actual lesson moved AFTER withdrawal.
  --
  -- MUST BE DELETED.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    rescheduled_by
  )
  values (
    v_series_a,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-28 18:00:00+09',
    timestamptz '2004-06-20 18:00:00+09',
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_4,
    v_manager_id
  )
  returning id
  into v_lesson_moved_after;


  -- Exactly at 00:00-day boundary's calendar date.
  -- 6/15 actual lesson -> delete.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id
  )
  values (
    v_series_b,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-15 19:00:00+09',
    timestamptz '2004-06-15 19:00:00+09',
    30,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    v_right_5
  )
  returning id
  into v_lesson_boundary;


  -- Future canceled lesson.
  insert into public.lessons (
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values (
    v_series_c,
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2004-06-16 20:00:00+09',
    timestamptz '2004-06-16 20:00:00+09',
    30,
    'regular'::public.lesson_type,
    'canceled'::public.lesson_status,
    v_right_6,
    v_manager_id,
    timestamptz '2004-06-10 12:00:00+09',
    'withdrawal-test'
  )
  returning id
  into v_lesson_canceled_future;


  -- ==========================================================
  -- 10. IMMUTABLE CANCELLATION LEDGER
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    canceled_at,
    reason
  )
  values (
    v_lesson_canceled_future,
    v_right_6,
    v_student_id,
    v_branch_id,
    'academy'::public.lesson_cancellation_origin,
    v_manager_id,
    false,
    timestamptz '2004-06-10 12:00:00+09',
    'withdrawal-test'
  )
  returning id
  into v_cancellation_event_id;


  -- ==========================================================
  -- 11. LEGACY CREDIT
  --
  -- Still references lesson with ON DELETE RESTRICT,
  -- therefore withdrawal must remove this compatibility row.
  -- ==========================================================

  insert into public.lesson_rebooking_credits (
    student_id,
    source_lesson_id,
    source_series_id,
    source_semester_id,
    usable_semester_id,
    teacher_id,
    duration_minutes,
    cancellation_no,
    status,
    carryover_count,
    credit_origin
  )
  values (
    v_student_id,
    v_lesson_canceled_future,
    v_series_c,
    v_semester_id,
    v_semester_id,
    v_teacher_id,
    30,
    null,
    'available'::public.rebooking_credit_status,
    0,
    'master_cancellation'::public.rebooking_credit_origin
  )
  returning id
  into v_legacy_credit_id;


  -- ==========================================================
  -- 12. STUDENT CANNOT FINALIZE OWN WITHDRAWAL
  -- ==========================================================

  update public.students
  set withdrawal_date =
      v_today + 1
  where id =
        v_student_id;


  perform set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
    true
  );

  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  begin

    perform public.finalize_student_withdrawal(
      v_student_id
    );

    raise exception
      'TEST_FAILED: student finalized own withdrawal';

  exception
    when others then

      if sqlerrm <>
         'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN' then
        raise;
      end if;

  end;


  -- ==========================================================
  -- 13. LOGIN AS MANAGER
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 14. FUTURE WITHDRAWAL DATE MUST NOT FINALIZE EARLY
  -- ==========================================================

  update public.students
  set withdrawal_date =
      v_today + 1
  where id =
        v_student_id;


  begin

    perform public.finalize_student_withdrawal(
      v_student_id
    );

    raise exception
      'TEST_FAILED: future withdrawal finalized early';

  exception
    when others then

      if sqlerrm <>
         'FORESTRING_STUDENT_WITHDRAWAL_NOT_READY' then
        raise;
      end if;

  end;


  if not exists (
    select 1
    from public.students s
    where s.id = v_student_id
      and s.status =
          'active'::public.student_status
  ) then
    raise exception
      'TEST_FAILED: not-ready call mutated student status';
  end if;


  if not exists (
    select 1
    from public.profiles p
    where p.id = v_student_id
      and p.is_active = true
  ) then
    raise exception
      'TEST_FAILED: not-ready call deactivated profile';
  end if;


  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_boundary
  ) then
    raise exception
      'TEST_FAILED: not-ready call deleted future lesson';
  end if;


  -- ==========================================================
  -- 15. SET EFFECTIVE HISTORICAL WITHDRAWAL
  -- ==========================================================

  update public.students
  set withdrawal_date =
      date '2004-06-15'
  where id =
        v_student_id;


  -- ==========================================================
  -- 16. FINALIZE
  -- ==========================================================

  v_result :=
    public.finalize_student_withdrawal(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     true then

    raise exception
      'TEST_FAILED: successful withdrawal returned changed=false: %',
      v_result;

  end if;


  if (v_result ->> 'deletedLessonCount')::integer <
     3 then

    raise exception
      'TEST_FAILED: expected at least 3 deleted lessons: %',
      v_result;

  end if;


  if (v_result ->> 'preservedCancellationEventCount')::integer <
     1 then

    raise exception
      'TEST_FAILED: cancellation ledger was not counted as preserved: %',
      v_result;

  end if;


  if (v_result ->> 'deletedLegacyCreditCount')::integer <
     1 then

    raise exception
      'TEST_FAILED: legacy credit was not deleted: %',
      v_result;

  end if;


  -- ==========================================================
  -- 17. STUDENT / PROFILE STATE
  -- ==========================================================

  if not exists (
    select 1

    from public.students s

    where s.id =
          v_student_id

      and s.status =
          'withdrawn'::public.student_status

      and s.withdrawal_date =
          date '2004-06-15'
  ) then

    raise exception
      'TEST_FAILED: student withdrawal state incorrect';

  end if;


  if not exists (
    select 1

    from public.profiles p

    where p.id =
          v_student_id

      and p.is_active =
          false
  ) then

    raise exception
      'TEST_FAILED: withdrawn profile still active';

  end if;


  -- ==========================================================
  -- 18. starts_at BEFORE CUTOFF -> PRESERVED
  -- ==========================================================

  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_past
  ) then
    raise exception
      'TEST_FAILED: historical lesson deleted';
  end if;


  if not exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_past_2
  ) then
    raise exception
      'TEST_FAILED: second historical lesson deleted';
  end if;


  -- Critical:
  -- occurrence is future, but actual starts_at is before cutoff.
  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_lesson_moved_before

      and l.occurrence_at =
          timestamptz '2004-06-21 18:00:00+09'

      and l.starts_at =
          timestamptz '2004-06-14 19:00:00+09'
  ) then

    raise exception
      'TEST_FAILED: lesson moved before withdrawal was deleted';
  end if;


  -- ==========================================================
  -- 19. starts_at ON/AFTER CUTOFF -> HARD DELETE
  -- ==========================================================

  if exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_moved_after
  ) then
    raise exception
      'TEST_FAILED: lesson moved after withdrawal survived';
  end if;


  if exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_boundary
  ) then
    raise exception
      'TEST_FAILED: withdrawal-date lesson survived';
  end if;


  if exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_canceled_future
  ) then
    raise exception
      'TEST_FAILED: canceled future lesson survived';
  end if;


  -- ==========================================================
  -- 20. CANCELLATION LEDGER SURVIVES LESSON DELETION
  -- ==========================================================

  if not exists (
    select 1

    from public.lesson_cancellation_events e

    where e.id =
          v_cancellation_event_id

      and e.lesson_id =
          v_lesson_canceled_future

      and e.lesson_right_id =
          v_right_6
  ) then

    raise exception
      'TEST_FAILED: immutable cancellation ledger was removed';
  end if;


  -- Referenced lesson should truly be gone.
  if exists (
    select 1
    from public.lessons l
    where l.id =
          v_lesson_canceled_future
  ) then
    raise exception
      'TEST_FAILED: cancellation test lesson still exists';
  end if;


  -- ==========================================================
  -- 21. LEGACY CREDIT MUST BE GONE
  -- ==========================================================

  if exists (
    select 1

    from public.lesson_rebooking_credits c

    where c.id =
          v_legacy_credit_id
  ) then

    raise exception
      'TEST_FAILED: legacy credit survived withdrawal';
  end if;


  -- ==========================================================
  -- 22. PRESERVED HISTORICAL RESERVED RIGHTS -> CONSUMED
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_right_1,
    v_right_2,
    v_right_3
  )

    and r.status =
        'consumed'::public.lesson_right_status

    and r.consumed_at is not null;


  if v_count <> 3 then

    raise exception
      'TEST_FAILED: expected 3 historical rights consumed, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 23. FUTURE / UNUSED RIGHTS -> REVOKED
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.id in (
    v_right_4,
    v_right_5,
    v_right_6
  )

    and r.status =
        'revoked'::public.lesson_right_status

    and r.revoked_at is not null;


  if v_count <> 3 then

    raise exception
      'TEST_FAILED: expected 3 future rights revoked, got %',
      v_count;

  end if;


  -- ==========================================================
  -- 24. ASSIGNMENT HISTORY
  -- ==========================================================

  if not exists (
    select 1

    from public.teacher_student_assignments a

    where a.id =
          v_assignment_id

      and a.ends_on =
          date '2004-06-14'
  ) then

    raise exception
      'TEST_FAILED: active assignment not closed on withdrawal - 1';
  end if;


  if exists (
    select 1

    from public.teacher_student_assignments a

    where a.id =
          v_future_assignment_id
  ) then

    raise exception
      'TEST_FAILED: future assignment survived withdrawal';
  end if;


  -- ==========================================================
  -- 25. REGULAR SERIES HISTORY
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_series ls

  where ls.id in (
    v_series_a,
    v_series_b,
    v_series_c
  )

    and ls.effective_until =
        date '2004-06-14';


  if v_count <> 3 then

    raise exception
      'TEST_FAILED: existing series not closed at withdrawal boundary';
  end if;


  if exists (
    select 1

    from public.lesson_series ls

    where ls.id =
          v_future_series
  ) then

    raise exception
      'TEST_FAILED: pure future series survived withdrawal';
  end if;


  -- ==========================================================
  -- 26. REGULAR SLOT HISTORY
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.regular_schedule_slots rs

  where rs.id in (
    v_slot_a,
    v_slot_b,
    v_slot_c
  )

    and rs.ends_on =
        date '2004-06-14';


  if v_count <> 3 then

    raise exception
      'TEST_FAILED: regular slots not closed on withdrawal - 1';
  end if;


  if not exists (
    select 1

    from public.regular_schedule_slots rs

    where rs.id =
          v_future_slot

      and rs.starts_on =
          date '2004-07-01'

      and rs.ends_on =
          date '2004-07-01'
  ) then

    raise exception
      'TEST_FAILED: pure future logical slot not tombstoned';
  end if;


  -- ==========================================================
  -- 27. HIGH-LEVEL AUDIT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_WITHDRAWAL_FINALIZED'

    and a.subject_profile_id =
        v_student_id

    and a.effective_on =
        date '2004-06-15';


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: expected one withdrawal audit, got %',
      v_count;

  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'STUDENT_WITHDRAWAL_FINALIZED'

      and a.subject_profile_id =
          v_student_id

      and a.effective_on =
          date '2004-06-15'

      and (
        a.details -> 'deletedLessonIds'
      ) ? v_lesson_moved_after::text

      and (
        a.details -> 'deletedLessonIds'
      ) ? v_lesson_boundary::text

      and (
        a.details -> 'deletedLessonIds'
      ) ? v_lesson_canceled_future::text

      and (
        a.details ->>
        'preservedCancellationEventCount'
      )::integer >= 1

      and (
        a.details ->>
        'deletedLegacyCreditCount'
      )::integer >= 1
  ) then

    raise exception
      'TEST_FAILED: withdrawal audit details incomplete';
  end if;


  -- ==========================================================
  -- 28. IDEMPOTENT SECOND CALL
  -- ==========================================================

  v_result :=
    public.finalize_student_withdrawal(
      v_student_id
    );


  if (v_result ->> 'changed')::boolean <>
     false then

    raise exception
      'TEST_FAILED: repeated withdrawal not idempotent: %',
      v_result;

  end if;


  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'STUDENT_WITHDRAWAL_FINALIZED'

    and a.subject_profile_id =
        v_student_id

    and a.effective_on =
        date '2004-06-15';


  if v_count <> 1 then

    raise exception
      'TEST_FAILED: repeated finalize duplicated audit';

  end if;

end;
$$;


select
  'PASS: student withdrawal finalization / starts_at boundary hard delete / moved-before preserve / moved-after delete / cancellation ledger preserved / legacy credit removed / rights consumed+revoked / assignment+series+slot closure / profile deactivation / not-ready guard / authorization / audit / idempotency'
  as test_result;

rollback;
