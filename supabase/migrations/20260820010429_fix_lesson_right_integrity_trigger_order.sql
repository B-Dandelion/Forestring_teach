-- ============================================================
-- Forestring v3
-- Fix lesson/right integrity trigger ordering
--
-- lessons.branch_id is derived by the existing BEFORE trigger
-- lessons_set_branch.
--
-- Lesson/right integrity therefore must run AFTER the row has
-- received its canonical branch.
-- ============================================================


-- Remove the old BEFORE trigger.
drop trigger if exists
  lessons_assert_lesson_right_integrity
on public.lessons;


-- INSERT validation:
-- lessons_set_branch has already populated branch_id.
create trigger lessons_assert_lesson_right_after_insert
after insert
on public.lessons
for each row
execute function public.assert_lesson_right_integrity();


-- UPDATE validation:
-- Validate whenever identity-relevant fields change.
create trigger lessons_assert_lesson_right_after_update
after update of
  lesson_right_id,
  student_id,
  branch_id,
  lesson_type
on public.lessons
for each row
execute function public.assert_lesson_right_integrity();


comment on function public.assert_lesson_right_integrity() is
  'Validates canonical lesson/right student, branch and lesson-type identity. Runs AFTER lesson branch derivation.';