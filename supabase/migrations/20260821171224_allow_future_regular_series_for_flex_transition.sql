-- ============================================================
-- Forestring v3
-- Allow future regular schedule preconfiguration for a student
-- who is currently flex but has a planned/active REGULAR
-- semester plan covering the series start date.
--
-- Current flex students still cannot have arbitrary regular
-- lesson_series.
-- ============================================================


create or replace function public.set_lesson_series_branch()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  teacher_branch uuid;
  student_branch uuid;
  current_student_type public.student_type;

  v_future_regular_plan_exists boolean := false;
begin

  -- ==========================================================
  -- TEACHER BRANCH
  -- ==========================================================

  select p.branch_id
  into teacher_branch

  from public.profiles p

  where p.id =
        new.teacher_id;


  -- ==========================================================
  -- STUDENT BRANCH + CURRENT TYPE
  -- ==========================================================

  select
    p.branch_id,
    s.student_type

  into
    student_branch,
    current_student_type

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        new.student_id;


  -- ==========================================================
  -- REQUIRED BRANCHES
  -- ==========================================================

  if teacher_branch is null
     or student_branch is null then

    raise exception
      'FORESTRING_BRANCH_REQUIRED';

  end if;


  -- ==========================================================
  -- SAME BRANCH
  -- ==========================================================

  if teacher_branch <>
     student_branch then

    raise exception
      'FORESTRING_BRANCH_MISMATCH';

  end if;


  -- ==========================================================
  -- CURRENT FLEX STUDENT
  --
  -- Normally a flex student must not have lesson_series.
  --
  -- Exception:
  --   a REGULAR semester plan has already been prepared for
  --   the same student/branch, and this series begins inside
  --   that regular semester.
  --
  -- This allows:
  --
  --   August: current student_type = flex
  --   September plan = regular/planned
  --   September regular schedule configured in August
  --
  -- without prematurely changing students.student_type.
  -- ==========================================================

  if current_student_type =
     'flex'::public.student_type then

    select exists (
      select 1

      from public.student_semester_plans sp

      cross join lateral
        private.get_effective_semester_bounds(
          sp.branch_id,
          sp.semester_id
        ) semester_bounds

      where sp.student_id =
            new.student_id

        and sp.branch_id =
            student_branch

        and sp.student_type_snapshot =
            'regular'::public.student_type

        and sp.status in (
          'planned'::public.student_semester_plan_status,
          'active'::public.student_semester_plan_status
        )

        -- The regular series must BEGIN within the semester
        -- that is actually configured as regular.
        and new.effective_from between
            semester_bounds.starts_on
            and semester_bounds.ends_on

        -- If the series already has an explicit end date,
        -- it cannot end before its regular-plan semester begins.
        and (
          new.effective_until is null
          or new.effective_until >=
             semester_bounds.starts_on
        )
    )
    into v_future_regular_plan_exists;


    if not v_future_regular_plan_exists then

      raise exception
        'FORESTRING_FLEX_STUDENT_CANNOT_HAVE_SERIES';

    end if;

  end if;


  -- ==========================================================
  -- BRANCH SNAPSHOT
  --
  -- Client/input branch is not trusted.
  -- ==========================================================

  new.branch_id :=
    teacher_branch;


  return new;

end;
$$;


comment on function public.set_lesson_series_branch() is
  'Derives lesson_series branch from teacher/student membership and prevents arbitrary recurring series for flex students. A currently-flex student may preconfigure a series only when its effective_from falls within a planned/active regular semester plan for the same student and branch.';