-- ============================================================
-- Forestring v3
-- Final foundation adjustments before feature RPC development
-- ============================================================


-- ============================================================
-- REBOOKING CREDIT ORIGIN
--
-- Student cancellation:
--   - creates a rebooking credit
--   - counts toward the per-series / per-semester limit of 2
--
-- Master cancellation:
--   - creates a rebooking credit
--   - DOES NOT count toward the student's cancellation limit
-- ============================================================

create type public.rebooking_credit_origin as enum (
  'student_cancellation',
  'master_cancellation'
);


alter table public.lesson_rebooking_credits
add column credit_origin public.rebooking_credit_origin
not null
default 'student_cancellation';


-- cancellation_no used to be required for every credit.
--
-- It now means:
--
-- student_cancellation:
--   1 or 2
--
-- master_cancellation:
--   NULL
alter table public.lesson_rebooking_credits
alter column cancellation_no drop not null;


alter table public.lesson_rebooking_credits
drop constraint if exists
  lesson_rebooking_credits_cancellation_no_check;


alter table public.lesson_rebooking_credits
add constraint lesson_rebooking_credits_cancellation_origin_check
check (
  (
    credit_origin =
      'student_cancellation'::public.rebooking_credit_origin
    and cancellation_no between 1 and 2
  )
  or
  (
    credit_origin =
      'master_cancellation'::public.rebooking_credit_origin
    and cancellation_no is null
  )
);


create index lesson_rebooking_credits_origin_idx
on public.lesson_rebooking_credits(
  credit_origin,
  source_semester_id,
  source_series_id
);


comment on column public.lesson_rebooking_credits.credit_origin is
  'Why the replacement right was issued. Student cancellations count toward the per-series semester limit; master cancellations do not.';


comment on column public.lesson_rebooking_credits.cancellation_no is
  'Student cancellation sequence number within a lesson series and semester. NULL for master-issued replacement rights.';


-- ============================================================
-- STUDENT SCHEDULED WITHDRAWAL
--
-- Previous rule:
--
-- active
--   -> withdrawal_date MUST be NULL
--
-- withdrawn
--   -> withdrawal_date MUST exist
--
-- New rule:
--
-- active + NULL
--   -> currently enrolled
--
-- active + future withdrawal_date
--   -> scheduled to withdraw
--
-- withdrawn + withdrawal_date
--   -> withdrawal completed
--
-- Date finalization will later be handled by RPC/Cron.
-- ============================================================

alter table public.students
drop constraint if exists
  students_withdrawal_state_check;


alter table public.students
add constraint students_withdrawal_state_check
check (
  status = 'active'::public.student_status

  or

  (
    status = 'withdrawn'::public.student_status
    and withdrawal_date is not null
  )
);


create index if not exists students_withdrawal_date_idx
on public.students(withdrawal_date)
where withdrawal_date is not null;


comment on column public.students.withdrawal_date is
  'Effective withdrawal date. May be set in advance while the student remains active.';


-- ============================================================
-- TEACHER SCHEDULED WITHDRAWAL
--
-- Teacher records are preserved after withdrawal so historical
-- lessons can continue resolving teacher identity/name.
--
-- Actual deactivation will later set profiles.is_active = false.
-- ============================================================

alter table public.teachers
add column withdrawal_date date;


create index teachers_withdrawal_date_idx
on public.teachers(withdrawal_date)
where withdrawal_date is not null;


comment on column public.teachers.withdrawal_date is
  'Effective teacher withdrawal date. Historical teacher and lesson records remain preserved after deactivation.';


-- ============================================================
-- REBOOKING CREDIT RLS HARDENING
--
-- Direct credit visibility:
--
-- master
--   -> all
--
-- student
--   -> own only
--
-- teachers do not need direct credit-table access.
-- Cancellation history remains represented by lessons.
-- ============================================================

drop policy if exists lesson_rebooking_credits_select
on public.lesson_rebooking_credits;


create policy lesson_rebooking_credits_select
on public.lesson_rebooking_credits
for select
to authenticated
using (
  (select private.is_active_user())
  and
  (
    (select private.is_master())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- DOCUMENT CURRENT INTENT
--
-- The current public.cancel_lesson() RPC creates student-origin
-- credits. The default above preserves that behavior.
--
-- A future master cancellation RPC MUST explicitly insert:
--
--   credit_origin = 'master_cancellation'
--   cancellation_no = NULL
--
-- Master cancellation therefore never consumes either of the
-- student's two allowed cancellation numbers.
-- ============================================================
