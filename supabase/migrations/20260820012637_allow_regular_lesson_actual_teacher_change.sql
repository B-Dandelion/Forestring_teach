-- ============================================================
-- Forestring v3
-- Allow actual regular lesson teacher to differ from the
-- historical lesson-series teacher.
--
-- Why:
--
-- lesson_series
--   = recurring rule / generation provenance
--
-- lessons.teacher_id
--   = actual teacher currently teaching that lesson
--
-- Example:
--
-- original occurrence generated from:
--   series teacher A
--
-- later assignment:
--   teacher B
--
-- student cancels + rebooks:
--   same lesson
--   same series provenance
--   same occurrence_at
--   actual teacher becomes B
--
-- Student identity MUST still match the originating series.
-- ============================================================


-- ============================================================
-- 1. SERIES STUDENT IDENTITY
--
-- Required for the new composite FK below.
-- ============================================================

alter table public.lesson_series
add constraint lesson_series_student_identity_unique
unique (
  id,
  student_id
);


-- ============================================================
-- 2. REMOVE OLD OVER-STRICT FK
--
-- Old meaning:
--   actual lesson teacher MUST equal series teacher
--
-- This prevents legitimate reassignment/rebooking.
-- ============================================================

alter table public.lessons
drop constraint if exists
  lessons_series_identity_fk;


-- ============================================================
-- 3. KEEP SERIES/STUDENT PROVENANCE INTEGRITY
--
-- A regular lesson may never point to another student's series.
--
-- Actual teacher is intentionally not part of this FK.
-- ============================================================

alter table public.lessons
add constraint lessons_series_student_identity_fk
foreign key (
  series_id,
  student_id
)
references public.lesson_series (
  id,
  student_id
)
on delete restrict;


comment on constraint
  lessons_series_student_identity_fk
on public.lessons
is
  'Regular lesson keeps originating series/student provenance. Actual lesson teacher may differ from historical series teacher after assignment changes or rebooking.';


comment on column public.lessons.teacher_id
is
  'Actual teacher responsible for this lesson instance. May differ from lesson_series.teacher_id after reassignment/rebooking.';


comment on column public.lessons.series_id
is
  'Recurring-rule provenance for a regular lesson. The series teacher is historical generation context and does not permanently lock the actual lesson teacher.';