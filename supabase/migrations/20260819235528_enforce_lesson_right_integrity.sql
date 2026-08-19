-- ============================================================
-- Forestring v3
-- Canonical lesson <-> lesson right integrity
-- ============================================================


create or replace function public.assert_lesson_right_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_right_student_id uuid;
  v_right_branch_id uuid;
  v_right_origin public.lesson_right_origin;
begin

  if new.lesson_right_id is null then
    return new;
  end if;


  select
    r.student_id,
    r.branch_id,
    r.origin
  into
    v_right_student_id,
    v_right_branch_id,
    v_right_origin
  from public.lesson_rights r
  where r.id = new.lesson_right_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_RIGHT_NOT_FOUND';
  end if;


  if new.student_id <>
     v_right_student_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_RIGHT_STUDENT_MISMATCH';

  end if;


  if new.branch_id is distinct from
     v_right_branch_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_RIGHT_BRANCH_MISMATCH';

  end if;


  -- Regular base entitlement creates a regular lesson.
  if v_right_origin =
       'regular_base'::public.lesson_right_origin
     and new.lesson_type <>
       'regular'::public.lesson_type then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_RIGHT_REQUIRES_REGULAR_LESSON';

  end if;


  -- Flex base entitlement creates a flex lesson.
  if v_right_origin =
       'flex_base'::public.lesson_right_origin
     and new.lesson_type <>
       'flex'::public.lesson_type then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FLEX_RIGHT_REQUIRES_FLEX_LESSON';

  end if;


  -- Carryover is freely bookable and therefore represented as
  -- a standalone flex-style booking regardless of whether the
  -- original entitlement came from regular or flex.
  if v_right_origin =
       'carryover'::public.lesson_right_origin
     and new.lesson_type <>
       'flex'::public.lesson_type then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CARRYOVER_RIGHT_REQUIRES_FLEX_LESSON';

  end if;


  return new;
end;
$$;


create trigger lessons_assert_lesson_right_integrity
before insert
or update of
  lesson_right_id,
  student_id,
  branch_id,
  lesson_type
on public.lessons
for each row
execute function public.assert_lesson_right_integrity();