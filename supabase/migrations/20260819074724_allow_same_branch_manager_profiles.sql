drop policy if exists profiles_select
on public.profiles;


create policy profiles_select
on public.profiles
for select
to authenticated
using (
  (select private.is_active_user())
  and (
    -- master: 모든 profile
    (select private.is_master())

    -- 자기 자신
    or id = (select auth.uid())

    -- manager:
    -- 같은 지점의 manager / teacher / student
    or (
      (select private.is_manager())
      and branch_id = (
        select private.current_branch_id()
      )
      and role in (
        'manager'::public.user_role,
        'teacher'::public.user_role,
        'student'::public.user_role
      )
    )

    -- teacher:
    -- 담당 학생
    or (
      role = 'student'::public.user_role
      and private.teacher_has_student_relation(id)
    )

    -- student:
    -- 담당 선생님
    -- 담당자가 수업 겸임 manager일 수도 있음
    or (
      role in (
        'teacher'::public.user_role,
        'manager'::public.user_role
      )
      and private.student_has_teacher_relation(id)
    )
  )
);