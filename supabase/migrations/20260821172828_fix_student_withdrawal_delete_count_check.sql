-- ============================================================
-- Forestring v3
-- Finalize scheduled student withdrawal
--
-- Policy:
--   - withdrawal becomes effective at 00:00 KST
--   - actual lessons whose starts_at is on/after that boundary
--     are HARD DELETED
--   - past actual lessons remain
--   - unused active lesson rights are revoked
--   - completed/past rights remain historical
--   - assignment / recurring schedules are closed
--   - profile becomes inactive
--
-- Scheduling / canceling a future withdrawal is handled by
-- separate RPCs.
-- ============================================================


create or replace function public.finalize_student_withdrawal(
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_branch_id uuid;
  v_student_status public.student_status;
  v_withdrawal_date date;
  v_profile_active boolean;

  v_today date;
  v_cutoff timestamptz;

  v_future_lesson_ids uuid[] :=
    '{}'::uuid[];

  v_future_right_ids uuid[] :=
    '{}'::uuid[];

  v_deleted_lesson_count integer := 0;
  v_actual_deleted_lesson_count integer := 0;

  v_deleted_cancellation_count integer := 0;
  v_deleted_legacy_credit_count integer := 0;

  v_consumed_right_count integer := 0;
  v_revoked_right_count integer := 0;

  v_closed_assignment_count integer := 0;
  v_deleted_future_assignment_count integer := 0;

  v_closed_series_count integer := 0;
  v_deleted_future_series_count integer := 0;
  v_tombstoned_future_series_count integer := 0;

  v_closed_slot_count integer := 0;
  v_tombstoned_future_slot_count integer := 0;
begin

  -- ==========================================================
  -- 1. ACTOR AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 2. LOCK STUDENT + PROFILE
  --
  -- Subject profile may already be inactive on a repeated call,
  -- so do NOT filter p.is_active here.
  -- ==========================================================

  select
    p.branch_id,
    p.is_active,
    s.status,
    s.withdrawal_date

  into
    v_branch_id,
    v_profile_active,
    v_student_status,
    v_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        p_student_id

  for update of s, p;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- 3. MANAGER BRANCH
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 4. IDEMPOTENT ALREADY-WITHDRAWN CALL
  -- ==========================================================

  if v_student_status =
     'withdrawn'::public.student_status then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'withdrawalDate',
        v_withdrawal_date,

      'deletedLessonCount',
        0,

      'revokedRightCount',
        0
    );

  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_INVALID_STATE';

  end if;


  -- ==========================================================
  -- 5. WITHDRAWAL MUST HAVE BEEN SCHEDULED
  -- ==========================================================

  if v_withdrawal_date is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_withdrawal_date >
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_NOT_READY';

  end if;


  -- 00:00 KST on the effective withdrawal date.
  --
  -- starts_at >= this timestamp is no longer a real lesson.
  v_cutoff :=
    (
      v_withdrawal_date::timestamp
      at time zone 'Asia/Seoul'
    );


  -- ==========================================================
  -- 6. LOCK FUTURE ACTUAL LESSONS
  --
  -- Actual starts_at is authoritative.
  -- occurrence_at is NOT used for withdrawal deletion.
  -- ==========================================================

  perform 1

  from public.lessons l

  where l.student_id =
        p_student_id

    and l.starts_at >=
        v_cutoff

  for update;


  select
    coalesce(
      array_agg(
        l.id
        order by l.starts_at, l.id
      ),
      '{}'::uuid[]
    ),

    coalesce(
      array_agg(
        distinct l.lesson_right_id
      ) filter (
        where l.lesson_right_id is not null
      ),
      '{}'::uuid[]
    ),

    count(*)::integer

  into
    v_future_lesson_ids,
    v_future_right_ids,
    v_deleted_lesson_count

  from public.lessons l

  where l.student_id =
        p_student_id

    and l.starts_at >=
        v_cutoff;


  -- ==========================================================
  -- 7. REMOVE DEPENDENCIES OF FUTURE LESSONS
  --
  -- Cancellation ledger rows for lessons that are being
  -- physically removed are also removed.
  --
  -- Audit events remain immutable and untouched.
  -- ==========================================================

  delete from public.lesson_cancellation_events e

  where e.lesson_id =
        any(v_future_lesson_ids);


  get diagnostics
    v_deleted_cancellation_count =
      row_count;


  -- Legacy compatibility table still has ON DELETE RESTRICT
  -- against lessons. Remove only rows whose source lesson is
  -- itself being removed by withdrawal.
  delete from public.lesson_rebooking_credits c

  where c.source_lesson_id =
        any(v_future_lesson_ids);


  get diagnostics
    v_deleted_legacy_credit_count =
      row_count;


  -- ==========================================================
  -- 8. HARD DELETE FUTURE LESSONS
  -- ==========================================================

  delete from public.lessons l

  where l.id =
        any(v_future_lesson_ids);


  get diagnostics
    v_actual_deleted_lesson_count =
      row_count;


  -- Guard against concurrent / unexpected count mismatch.
  if v_actual_deleted_lesson_count <>
     v_deleted_lesson_count then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWAL_LESSON_DELETE_COUNT_MISMATCH';

  end if;


  -- ==========================================================
  -- 9. FINALIZE PAST RESERVED RIGHTS
  --
  -- A reserved entitlement with a remaining scheduled lesson
  -- before withdrawal represents a lesson that belongs to the
  -- preserved historical side of the boundary.
  --
  -- This mirrors semester finalization semantics.
  -- ==========================================================

  update public.lesson_rights r

  set
    status =
      'consumed'::public.lesson_right_status,

    consumed_at =
      coalesce(
        r.consumed_at,
        pg_catalog.now()
      )

  where r.student_id =
        p_student_id

    and r.status =
        'reserved'::public.lesson_right_status

    and exists (
      select 1

      from public.lessons l

      where l.lesson_right_id =
            r.id

        and l.student_id =
            p_student_id

        and l.status =
            'scheduled'::public.lesson_status

        and l.starts_at <
            v_cutoff
    );


  get diagnostics
    v_consumed_right_count =
      row_count;


  -- ==========================================================
  -- 10. REVOKE EVERY REMAINING ACTIVE ENTITLEMENT
  --
  -- After withdrawal:
  --   available -> cannot be used
  --   dangling/future reserved -> cannot be used
  --
  -- consumed / expired / already revoked remain historical.
  -- ==========================================================

  update public.lesson_rights r

  set
    status =
      'revoked'::public.lesson_right_status,

    revoked_at =
      coalesce(
        r.revoked_at,
        pg_catalog.now()
      )

  where r.student_id =
        p_student_id

    and r.status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );


  get diagnostics
    v_revoked_right_count =
      row_count;


  -- ==========================================================
  -- 11. ASSIGNMENT HISTORY
  --
  -- Historical assignment before withdrawal remains.
  --
  -- Any assignment that had not even started yet is discarded.
  -- ==========================================================

  delete from public.teacher_student_assignments a

  where a.student_id =
        p_student_id

    and a.starts_on >=
        v_withdrawal_date;


  get diagnostics
    v_deleted_future_assignment_count =
      row_count;


  update public.teacher_student_assignments a

  set
    ends_on =
      v_withdrawal_date - 1

  where a.student_id =
        p_student_id

    and a.starts_on <
        v_withdrawal_date

    and (
      a.ends_on is null
      or a.ends_on >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_assignment_count =
      row_count;


  -- ==========================================================
  -- 12. REGULAR SERIES
  --
  -- Past/current recurring rules are closed the day before
  -- withdrawal.
  --
  -- Pure future versions with no remaining historical
  -- dependency are removed.
  -- ==========================================================

  update public.lesson_series ls

  set
    effective_until =
      v_withdrawal_date - 1

  where ls.student_id =
        p_student_id

    and ls.effective_from <
        v_withdrawal_date

    and (
      ls.effective_until is null
      or ls.effective_until >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_series_count =
      row_count;


  delete from public.lesson_series ls

  where ls.student_id =
        p_student_id

    and ls.effective_from >=
        v_withdrawal_date

    -- A one-off lesson moved to BEFORE withdrawal may still
    -- legitimately retain this historical series identity.
    and not exists (
      select 1
      from public.lessons l
      where l.series_id =
            ls.id
    )

    -- Temporary legacy compatibility safety.
    and not exists (
      select 1
      from public.lesson_rebooking_credits c
      where c.source_series_id =
            ls.id
    );


  get diagnostics
    v_deleted_future_series_count =
      row_count;


  -- Rare case:
  -- a future series survives because a preserved historical
  -- lesson/legacy row still references its identity.
  --
  -- Prevent it from remaining open-ended.
  update public.lesson_series ls

  set
    effective_until =
      ls.effective_from

  where ls.student_id =
        p_student_id

    and ls.effective_from >=
        v_withdrawal_date

    and (
      ls.effective_until is null
      or ls.effective_until >
         ls.effective_from
    );


  get diagnostics
    v_tombstoned_future_series_count =
      row_count;


  -- ==========================================================
  -- 13. LOGICAL REGULAR SLOTS
  --
  -- Existing slots close on withdrawal - 1.
  --
  -- Future slot rows may still be referenced by revoked rights,
  -- so they are retained as historical planned identities but
  -- bounded to one day rather than left open-ended.
  --
  -- Reactivation will create/select a fresh valid schedule
  -- instead of silently reviving these old plans.
  -- ==========================================================

  update public.regular_schedule_slots rs

  set
    ends_on =
      v_withdrawal_date - 1

  where rs.student_id =
        p_student_id

    and rs.starts_on <
        v_withdrawal_date

    and (
      rs.ends_on is null
      or rs.ends_on >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_slot_count =
      row_count;


  update public.regular_schedule_slots rs

  set
    ends_on =
      rs.starts_on

  where rs.student_id =
        p_student_id

    and rs.starts_on >=
        v_withdrawal_date

    and (
      rs.ends_on is null
      or rs.ends_on >
         rs.starts_on
    );


  get diagnostics
    v_tombstoned_future_slot_count =
      row_count;


  -- ==========================================================
  -- 14. STUDENT / PROFILE STATE
  -- ==========================================================

  update public.students
  set
    status =
      'withdrawn'::public.student_status

  where id =
        p_student_id;


  update public.profiles
  set
    is_active =
      false

  where id =
        p_student_id;


  -- ==========================================================
  -- 15. IMMUTABLE HIGH-LEVEL AUDIT
  --
  -- Lessons themselves are intentionally gone, but the admin
  -- action and deletion summary remain visible.
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_student_id,
    v_branch_id,
    null,
    'STUDENT_WITHDRAWAL_FINALIZED',
    v_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'withdrawalDate',
        v_withdrawal_date,

      'deletedLessonCount',
        v_deleted_lesson_count,

      'deletedLessonIds',
        to_jsonb(
          v_future_lesson_ids
        ),

      'deletedCancellationEventCount',
        v_deleted_cancellation_count,

      'deletedLegacyCreditCount',
        v_deleted_legacy_credit_count,

      'consumedHistoricalRightCount',
        v_consumed_right_count,

      'revokedRightCount',
        v_revoked_right_count,

      'closedAssignmentCount',
        v_closed_assignment_count,

      'deletedFutureAssignmentCount',
        v_deleted_future_assignment_count,

      'closedRegularSeriesCount',
        v_closed_series_count,

      'deletedFutureSeriesCount',
        v_deleted_future_series_count,

      'tombstonedFutureSeriesCount',
        v_tombstoned_future_series_count,

      'closedRegularSlotCount',
        v_closed_slot_count,

      'tombstonedFutureSlotCount',
        v_tombstoned_future_slot_count
    )
  );


  -- ==========================================================
  -- 16. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'withdrawalDate',
      v_withdrawal_date,

    'deletedLessonCount',
      v_deleted_lesson_count,

    'deletedCancellationEventCount',
      v_deleted_cancellation_count,

    'deletedLegacyCreditCount',
      v_deleted_legacy_credit_count,

    'consumedHistoricalRightCount',
      v_consumed_right_count,

    'revokedRightCount',
      v_revoked_right_count,

    'closedAssignmentCount',
      v_closed_assignment_count,

    'deletedFutureAssignmentCount',
      v_deleted_future_assignment_count,

    'closedRegularSeriesCount',
      v_closed_series_count,

    'deletedFutureSeriesCount',
      v_deleted_future_series_count,

    'tombstonedFutureSeriesCount',
      v_tombstoned_future_series_count,

    'closedRegularSlotCount',
      v_closed_slot_count,

    'tombstonedFutureSlotCount',
      v_tombstoned_future_slot_count
  );

end;
$$;


revoke all
on function public.finalize_student_withdrawal(
  uuid
)
from public, anon;


grant execute
on function public.finalize_student_withdrawal(
  uuid
)
to authenticated;


comment on function public.finalize_student_withdrawal(
  uuid
) is
  'Finalizes a scheduled student withdrawal once its KST effective date has arrived. Actual lessons whose starts_at is on/after the withdrawal boundary are hard-deleted together with lesson-bound cancellation/legacy-credit rows; historical lessons are preserved, remaining active rights are revoked, assignment/recurring schedules are closed, and the student profile is deactivated atomically.';