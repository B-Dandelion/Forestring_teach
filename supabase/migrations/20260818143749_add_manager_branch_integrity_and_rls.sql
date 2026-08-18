-- ============================================================
-- Forestring v3
-- Manager / branch integrity + RLS
-- ============================================================


-- ============================================================
-- MANAGER MAY ALSO BE A TEACHER
--
-- role = access authority
-- teachers row = can actually teach lessons
--
-- Therefore:
--   teacher role -> teachers row allowed
--   manager role -> teachers row also allowed
-- ============================================================

create or replace function public.assert_teacher_capable_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actual_role public.user_role;
begin
  select p.role
  into actual_role
  from public.profiles p
  where p.id = new.id;

  if not found then
    raise exception
      'FORESTRING_PROFILE_NOT_FOUND';
  end if;

  if actual_role not in (
    'teacher'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception
      'FORESTRING_PROFILE_CANNOT_TEACH';
  end if;

  return new;
end;
$$;


drop trigger if exists
teachers_assert_profile_role
on public.teachers;


create trigger teachers_assert_profile_role
before insert or update of id
on public.teachers
for each row
execute function public.assert_teacher_capable_role();


-- ============================================================
-- BRANCH INTEGRITY:
-- TEACHER <-> STUDENT ASSIGNMENT
-- ============================================================

create or replace function public.set_assignment_branch()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  teacher_branch uuid;
  student_branch uuid;
begin
  select p.branch_id
  into teacher_branch
  from public.profiles p
  where p.id = new.teacher_id;

  select p.branch_id
  into student_branch
  from public.profiles p
  where p.id = new.student_id;

  if teacher_branch is null
     or student_branch is null then
    raise exception
      'FORESTRING_BRANCH_REQUIRED';
  end if;

  if teacher_branch <> student_branch then
    raise exception
      'FORESTRING_BRANCH_MISMATCH';
  end if;

  new.branch_id := teacher_branch;

  return new;
end;
$$;


create trigger teacher_student_assignments_set_branch
before insert
or update of teacher_id, student_id, branch_id
on public.teacher_student_assignments
for each row
execute function public.set_assignment_branch();


-- ============================================================
-- BRANCH + STUDENT TYPE INTEGRITY:
-- LESSON SERIES
--
-- flex student MUST NOT receive a recurring lesson series.
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
begin
  select p.branch_id
  into teacher_branch
  from public.profiles p
  where p.id = new.teacher_id;

  select
    p.branch_id,
    s.student_type
  into
    student_branch,
    current_student_type
  from public.students s
  join public.profiles p
    on p.id = s.id
  where s.id = new.student_id;

  if teacher_branch is null
     or student_branch is null then
    raise exception
      'FORESTRING_BRANCH_REQUIRED';
  end if;

  if teacher_branch <> student_branch then
    raise exception
      'FORESTRING_BRANCH_MISMATCH';
  end if;

  if current_student_type <> 'regular'::public.student_type then
    raise exception
      'FORESTRING_FLEX_STUDENT_CANNOT_HAVE_SERIES';
  end if;

  new.branch_id := teacher_branch;

  return new;
end;
$$;


create trigger lesson_series_set_branch
before insert
or update of teacher_id, student_id, branch_id
on public.lesson_series
for each row
execute function public.set_lesson_series_branch();


-- ============================================================
-- BRANCH INTEGRITY:
-- ACTUAL LESSON
-- ============================================================

create or replace function public.set_lesson_branch()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  teacher_branch uuid;
  student_branch uuid;
  series_branch uuid;
begin
  select p.branch_id
  into teacher_branch
  from public.profiles p
  where p.id = new.teacher_id;

  select p.branch_id
  into student_branch
  from public.profiles p
  where p.id = new.student_id;

  if teacher_branch is null
     or student_branch is null then
    raise exception
      'FORESTRING_BRANCH_REQUIRED';
  end if;

  if teacher_branch <> student_branch then
    raise exception
      'FORESTRING_BRANCH_MISMATCH';
  end if;

  if new.series_id is not null then
    select s.branch_id
    into series_branch
    from public.lesson_series s
    where s.id = new.series_id;

    if series_branch is null then
      raise exception
        'FORESTRING_SERIES_BRANCH_REQUIRED';
    end if;

    if series_branch <> teacher_branch then
      raise exception
        'FORESTRING_SERIES_BRANCH_MISMATCH';
    end if;

    new.branch_id := series_branch;
  else
    new.branch_id := teacher_branch;
  end if;

  return new;
end;
$$;


create trigger lessons_set_branch
before insert
or update of teacher_id, student_id, series_id, branch_id
on public.lessons
for each row
execute function public.set_lesson_branch();


-- ============================================================
-- REBOOKING CREDIT BRANCH
--
-- Derive branch from source lesson.
-- Existing cancel_lesson() does not need to trust Flutter.
-- ============================================================

create or replace function public.set_rebooking_credit_branch()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  lesson_branch uuid;
begin
  select l.branch_id
  into lesson_branch
  from public.lessons l
  where l.id = new.source_lesson_id;

  if lesson_branch is null then
    raise exception
      'FORESTRING_SOURCE_LESSON_BRANCH_REQUIRED';
  end if;

  new.branch_id := lesson_branch;

  return new;
end;
$$;


create trigger lesson_rebooking_credits_set_branch
before insert
or update of source_lesson_id, branch_id
on public.lesson_rebooking_credits
for each row
execute function public.set_rebooking_credit_branch();


-- ============================================================
-- RLS HELPERS
-- ============================================================

create or replace function private.is_manager()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and p.role = 'manager'::public.user_role
  );
$$;


create or replace function private.current_branch_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.branch_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
  limit 1;
$$;


create or replace function private.manager_has_branch(
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select private.is_manager())
    and p_branch_id is not null
    and p_branch_id = (
      select private.current_branch_id()
    );
$$;


create or replace function private.manager_has_profile_branch(
  p_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles actor
    join public.profiles target
      on target.id = p_profile_id
    where actor.id = (select auth.uid())
      and actor.is_active = true
      and actor.role = 'manager'::public.user_role
      and actor.branch_id is not null
      and target.branch_id = actor.branch_id
  );
$$;


revoke all
on function private.is_manager()
from public, anon;

revoke all
on function private.current_branch_id()
from public, anon;

revoke all
on function private.manager_has_branch(uuid)
from public, anon;

revoke all
on function private.manager_has_profile_branch(uuid)
from public, anon;


grant execute
on function private.is_manager()
to authenticated;

grant execute
on function private.current_branch_id()
to authenticated;

grant execute
on function private.manager_has_branch(uuid)
to authenticated;

grant execute
on function private.manager_has_profile_branch(uuid)
to authenticated;


-- ============================================================
-- BRANCH TABLE PERMISSIONS
-- ============================================================

revoke all
on table public.branches
from anon;


revoke
  insert,
  update,
  delete,
  truncate,
  references,
  trigger
on table public.branches
from authenticated;


grant select
on table public.branches
to authenticated;


drop policy if exists branches_select
on public.branches;


create policy branches_select
on public.branches
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())
    or id = (
      select private.current_branch_id()
    )
  )
);


-- ============================================================
-- PROFILES
--
-- master:
--   all
--
-- manager:
--   own profile
--   teachers/students in same branch
--
-- teacher:
--   own + related students
--
-- student:
--   own + assigned teacher
-- ============================================================

drop policy if exists profiles_select
on public.profiles;


create policy profiles_select
on public.profiles
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or id = (select auth.uid())

    or (
      (select private.is_manager())
      and branch_id = (
        select private.current_branch_id()
      )
      and role in (
        'teacher'::public.user_role,
        'student'::public.user_role
      )
    )

    or (
      role = 'student'::public.user_role
      and private.teacher_has_student_relation(id)
    )

    or (
      role in (
        'teacher'::public.user_role,
        'manager'::public.user_role
      )
      and private.student_has_teacher_relation(id)
    )
  )
);


-- ============================================================
-- TEACHERS
-- ============================================================

drop policy if exists teachers_select
on public.teachers;


create policy teachers_select
on public.teachers
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or id = (select auth.uid())

    or private.manager_has_profile_branch(id)
  )
);


-- ============================================================
-- STUDENTS
-- ============================================================

drop policy if exists students_select
on public.students;


create policy students_select
on public.students
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or id = (select auth.uid())

    or private.manager_has_profile_branch(id)

    or private.teacher_has_student_relation(id)
  )
);


-- ============================================================
-- ASSIGNMENTS
-- ============================================================

drop policy if exists teacher_student_assignments_select
on public.teacher_student_assignments;


create policy teacher_student_assignments_select
on public.teacher_student_assignments
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or private.manager_has_branch(branch_id)

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- TEACHER WORK HOURS
-- ============================================================

drop policy if exists teacher_work_hours_select
on public.teacher_work_hours;


create policy teacher_work_hours_select
on public.teacher_work_hours
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or teacher_id = (select auth.uid())

    or private.manager_has_profile_branch(
      teacher_id
    )
  )
);


-- ============================================================
-- BLOCKED PERIODS
-- ============================================================

drop policy if exists blocked_periods_select
on public.blocked_periods;


create policy blocked_periods_select
on public.blocked_periods
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or teacher_id = (select auth.uid())

    or private.manager_has_profile_branch(
      teacher_id
    )
  )
);


-- ============================================================
-- LESSON SERIES
-- ============================================================

drop policy if exists lesson_series_select
on public.lesson_series;


create policy lesson_series_select
on public.lesson_series
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or private.manager_has_branch(branch_id)

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- LESSONS
-- ============================================================

drop policy if exists lessons_select
on public.lessons;


create policy lessons_select
on public.lessons
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or private.manager_has_branch(branch_id)

    or teacher_id = (select auth.uid())

    or student_id = (select auth.uid())
  )
);


-- ============================================================
-- REBOOKING CREDITS
--
-- Teachers do not need direct access.
-- Manager can inspect credits belonging to their branch.
-- ============================================================

drop policy if exists lesson_rebooking_credits_select
on public.lesson_rebooking_credits;


create policy lesson_rebooking_credits_select
on public.lesson_rebooking_credits
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    (select private.is_master())

    or private.manager_has_branch(branch_id)

    or student_id = (select auth.uid())
  )
);
