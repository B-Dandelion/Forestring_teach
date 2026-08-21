-- ============================================================
-- Forestring v3
-- Atomic student teacher reassignment
--
-- Regular:
--   assignment history changes
--   + regular default schedule teacher versions together
--
-- Flex:
--   assignment history changes only
--   existing booked actual lessons remain untouched
-- ============================================================


create or replace function public.change_student_teacher(
  p_student_id uuid,
  p_teacher_id uuid,
  p_effective_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_today date;

  v_student_branch_id uuid;
  v_student_status public.student_status;
  v_student_type public.student_type;
  v_student_withdrawal_date date;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_old_assignment
    public.teacher_student_assignments%rowtype;

  v_new_assignment_id uuid;
  v_new_assignment_ends_on date;

  v_slot record;
  v_series record;

  v_schedule_result jsonb;

  v_regular_slot_count integer := 0;
  v_schedule_change_count integer := 0;

  v_assignment_updated_in_place boolean := false;
begin

  -- ==========================================================
  -- 1. AUTH
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

  where p.id = v_actor_id
    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;


  -- 담당교사 변경은 관리 기능.
  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_CHANGE_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 2. EFFECTIVE DATE
  -- ==========================================================

  if p_effective_on is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EFFECTIVE_DATE_REQUIRED';
  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- Historical assignment is never silently rewritten.
  if p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BACKDATED_TEACHER_CHANGE_FORBIDDEN';
  end if;


  -- ==========================================================
  -- 3. LOCK STUDENT
  -- ==========================================================

  select
    p.branch_id,
    s.status,
    s.student_type,
    s.withdrawal_date

  into
    v_student_branch_id,
    v_student_status,
    v_student_type,
    v_student_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id = p_student_id
    and p.is_active = true

  for update of s;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_INACTIVE';

  end if;


  if v_student_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_student_withdrawal_date is not null
     and p_effective_on >=
         v_student_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_CHANGE_AFTER_STUDENT_WITHDRAWAL';

  end if;


  -- ==========================================================
  -- 4. MANAGER BRANCH
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_student_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 5. TARGET TEACHER
  --
  -- Managers are also teachers rows in the current model.
  -- ==========================================================

  select
    p.branch_id,
    p.is_active,
    t.withdrawal_date

  into
    v_teacher_branch_id,
    v_teacher_active,
    v_teacher_withdrawal_date

  from public.teachers t

  join public.profiles p
    on p.id = t.id

  where t.id = p_teacher_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;


  if v_teacher_active <> true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_INACTIVE';
  end if;


  if v_teacher_branch_id is distinct from
     v_student_branch_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_MISMATCH';

  end if;


  if v_teacher_withdrawal_date is not null
     and p_effective_on >=
         v_teacher_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';

  end if;


  -- ==========================================================
  -- 6. LOCK CURRENT ASSIGNMENT AT EFFECTIVE DATE
  -- ==========================================================

  select *
  into v_old_assignment

  from public.teacher_student_assignments a

  where a.student_id =
        p_student_id

    and a.starts_on <=
        p_effective_on

    and (
      a.ends_on is null
      or a.ends_on >=
         p_effective_on
    )

  order by a.starts_on desc

  limit 1

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CURRENT_TEACHER_ASSIGNMENT_NOT_FOUND';
  end if;


  -- ==========================================================
  -- 7. NO-OP
  -- ==========================================================

  if v_old_assignment.teacher_id =
     p_teacher_id then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'teacherId',
        p_teacher_id,

      'effectiveOn',
        p_effective_on,

      'assignmentId',
        v_old_assignment.id,

      'regularScheduleChangeCount',
        0
    );

  end if;


  -- ==========================================================
  -- 8. FUTURE ASSIGNMENT SAFETY
  --
  -- Do not silently overwrite another already-planned teacher
  -- change beyond this requested date.
  -- ==========================================================

  if exists (
    select 1

    from public.teacher_student_assignments a

    where a.student_id =
          p_student_id

      and a.starts_on >
          p_effective_on
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_FUTURE_TEACHER_ASSIGNMENT_EXISTS';

  end if;


  v_new_assignment_ends_on :=
    v_old_assignment.ends_on;


  -- ==========================================================
  -- 9. VERSION ASSIGNMENT
  --
  -- If a future assignment begins exactly on effective_on,
  -- correct it in-place.
  --
  -- Otherwise:
  --   old ends day before
  --   new begins effective_on
  -- ==========================================================

  if v_old_assignment.starts_on =
     p_effective_on then

    update public.teacher_student_assignments
    set
      teacher_id =
        p_teacher_id

    where id =
          v_old_assignment.id

    returning id
    into v_new_assignment_id;


    v_assignment_updated_in_place :=
      true;


  else

    update public.teacher_student_assignments
    set
      ends_on =
        p_effective_on - 1

    where id =
          v_old_assignment.id;


    begin

      insert into public.teacher_student_assignments (
        teacher_id,
        student_id,
        starts_on,
        ends_on
      )
      values (
        p_teacher_id,
        p_student_id,
        p_effective_on,
        v_new_assignment_ends_on
      )

      returning id
      into v_new_assignment_id;


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_ASSIGNMENT_PERIOD_OVERLAP';

    end;

  end if;


  -- ==========================================================
  -- 10. REGULAR STUDENT
  --
  -- Re-version every active logical regular slot using the
  -- SAME weekday/time/duration but the NEW teacher.
  --
  -- change_regular_schedule() already handles:
  --
  --   untouched future lessons -> reconcile
  --   canceled                 -> preserve
  --   one-off moved            -> preserve
  --   canceled/rebooked        -> preserve
  -- ==========================================================

  if v_student_type =
     'regular'::public.student_type then

    for v_slot in

      select
        rs.id

      from public.regular_schedule_slots rs

      where rs.student_id =
            p_student_id

        and rs.branch_id =
            v_student_branch_id

        and rs.starts_on <=
            p_effective_on

        and (
          rs.ends_on is null
          or rs.ends_on >=
             p_effective_on
        )

      order by
        rs.starts_on,
        rs.id

    loop

      v_regular_slot_count :=
        v_regular_slot_count + 1;


      -- Current/default series configuration effective on
      -- the teacher-change date.
      select
        ls.teacher_id,
        ls.weekday,
        ls.start_time,
        ls.duration_minutes

      into
        v_series

      from public.lesson_series ls

      where ls.schedule_slot_id =
            v_slot.id

        and ls.student_id =
            p_student_id

        and ls.branch_id =
            v_student_branch_id

        and ls.effective_from <=
            p_effective_on

        and (
          ls.effective_until is null
          or ls.effective_until >=
             p_effective_on
        )

      order by
        ls.effective_from desc

      limit 1;


      if not found then
        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SERIES_NOT_FOUND_FOR_TEACHER_CHANGE',
          detail =
            'schedule_slot_id=' ||
            v_slot.id::text;
      end if;


      -- Assignment has already been changed inside THIS SAME
      -- transaction, so change_regular_schedule() sees the new
      -- authoritative teacher relationship.
      v_schedule_result :=
        public.change_regular_schedule(
          v_slot.id,
          p_teacher_id,
          v_series.weekday::integer,
          v_series.start_time,
          v_series.duration_minutes,
          p_effective_on
        );


      if coalesce(
        (
          v_schedule_result
          ->> 'changed'
        )::boolean,
        false
      ) then

        v_schedule_change_count :=
          v_schedule_change_count + 1;

      end if;

    end loop;

  end if;


  -- ==========================================================
  -- 11. AUDIT
  --
  -- Schedule RPCs create their own detailed
  -- REGULAR_SCHEDULE_CHANGED audits.
  --
  -- This records the higher-level teacher assignment action.
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
    v_student_branch_id,
    null,
    'STUDENT_TEACHER_CHANGED',
    p_effective_on,
    v_actor_id,

    jsonb_build_object(
      'previousTeacherId',
        v_old_assignment.teacher_id,

      'newTeacherId',
        p_teacher_id,

      'previousAssignmentId',
        v_old_assignment.id,

      'newAssignmentId',
        v_new_assignment_id,

      'assignmentUpdatedInPlace',
        v_assignment_updated_in_place,

      'studentType',
        v_student_type,

      'regularSlotCount',
        v_regular_slot_count,

      'regularScheduleChangeCount',
        v_schedule_change_count
    )
  );


  -- ==========================================================
  -- 12. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'previousTeacherId',
      v_old_assignment.teacher_id,

    'teacherId',
      p_teacher_id,

    'effectiveOn',
      p_effective_on,

    'previousAssignmentId',
      v_old_assignment.id,

    'assignmentId',
      v_new_assignment_id,

    'assignmentUpdatedInPlace',
      v_assignment_updated_in_place,

    'studentType',
      v_student_type,

    'regularSlotCount',
      v_regular_slot_count,

    'regularScheduleChangeCount',
      v_schedule_change_count
  );

end;
$$;


revoke all
on function public.change_student_teacher(
  uuid,
  uuid,
  date
)
from public, anon;


grant execute
on function public.change_student_teacher(
  uuid,
  uuid,
  date
)
to authenticated;


comment on function public.change_student_teacher(
  uuid,
  uuid,
  date
) is
  'Atomically versions a student teacher assignment from an effective date. For regular students, all active logical regular schedule slots are re-versioned to the new teacher through change_regular_schedule(), which reconciles only untouched future regular lessons. Existing flex bookings and individually altered/canceled regular lessons remain actual historical appointments.';