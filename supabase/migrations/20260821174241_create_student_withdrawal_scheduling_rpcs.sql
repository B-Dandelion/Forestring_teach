-- ============================================================
-- Forestring v3
-- Student withdrawal scheduling / cancellation
-- ============================================================


-- ============================================================
-- 1. SCHEDULE WITHDRAWAL
-- ============================================================

create or replace function public.schedule_student_withdrawal(
  p_student_id uuid,
  p_withdrawal_date date
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
  v_status public.student_status;
  v_current_withdrawal_date date;

  v_today date;
begin

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
      message =
        'FORESTRING_ACTIVE_USER_REQUIRED';
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


  if p_withdrawal_date is null then
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


  if p_withdrawal_date <
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_DATE_IN_PAST';

  end if;


  select
    p.branch_id,
    s.status,
    s.withdrawal_date

  into
    v_branch_id,
    v_status,
    v_current_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        p_student_id

  for update of s, p;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_actor_role =
     'manager'::public.user_role

     and not private.manager_has_branch(
       v_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  if v_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_ACTIVE';

  end if;


  -- Idempotent.
  if v_current_withdrawal_date =
     p_withdrawal_date then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'withdrawalDate',
        p_withdrawal_date
    );

  end if;


  update public.students
  set withdrawal_date =
      p_withdrawal_date
  where id =
        p_student_id;


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
    'STUDENT_WITHDRAWAL_SCHEDULED',
    p_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'previousWithdrawalDate',
        v_current_withdrawal_date,

      'withdrawalDate',
        p_withdrawal_date
    )
  );


  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'previousWithdrawalDate',
      v_current_withdrawal_date,

    'withdrawalDate',
      p_withdrawal_date
  );

end;
$$;


revoke all
on function public.schedule_student_withdrawal(
  uuid,
  date
)
from public, anon;


grant execute
on function public.schedule_student_withdrawal(
  uuid,
  date
)
to authenticated;



-- ============================================================
-- 2. CANCEL SCHEDULED WITHDRAWAL
-- ============================================================

create or replace function public.cancel_student_withdrawal(
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
  v_status public.student_status;
  v_withdrawal_date date;

  v_today date;
begin

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
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
      message =
        'FORESTRING_ACTIVE_USER_REQUIRED';
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


  select
    p.branch_id,
    s.status,
    s.withdrawal_date

  into
    v_branch_id,
    v_status,
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
      message =
        'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  if v_actor_role =
     'manager'::public.user_role

     and not private.manager_has_branch(
       v_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  if v_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_NOT_ACTIVE';

  end if;


  if v_withdrawal_date is null then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'withdrawalDate',
        null
    );

  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- Once the effective date has arrived, the scheduled
  -- withdrawal must be finalized rather than "canceled".
  if v_withdrawal_date <=
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE';

  end if;


  update public.students
  set withdrawal_date =
      null
  where id =
        p_student_id;


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
    'STUDENT_WITHDRAWAL_CANCELED',
    v_today,
    v_actor_id,

    jsonb_build_object(
      'canceledWithdrawalDate',
        v_withdrawal_date
    )
  );


  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'canceledWithdrawalDate',
      v_withdrawal_date,

    'withdrawalDate',
      null
  );

end;
$$;


revoke all
on function public.cancel_student_withdrawal(
  uuid
)
from public, anon;


grant execute
on function public.cancel_student_withdrawal(
  uuid
)
to authenticated;