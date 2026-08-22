drop trigger lesson_series_set_branch
on public.lesson_series;

create trigger lesson_series_set_branch
before insert
or update of
  teacher_id,
  student_id,
  branch_id,
  effective_from
on public.lesson_series
for each row
execute function public.set_lesson_series_branch();