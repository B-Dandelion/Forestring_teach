-- ============================================================
-- Forestring v3
-- Teacher blocked-period management
--
-- Blocked periods are CURRENT one-off availability defaults.
-- Existing lessons are NEVER automatically moved or canceled.
-- ============================================================


-- ============================================================
-- CREATE / UPDATE BLOCKED PERIOD
-- ============================================================

create or replace function public.upsert_teacher_blocked_period(
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text default null,
  p_blocked_period_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_teacher_branch_id uuid;
  v_teacher_role public.user_role;
  v_teacher_active boolean;

  v_existing public.blocked_periods%rowtype;

  v_result_id uuid;
  v_normalized_reason text;

  v_before jsonb;
  v_after jsonb;

  v_lesson_overlap_count integer;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id := auth.uid();


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


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';

  end if;


  -- ==========================================================
  -- TARGET TEACHER
  -- ==========================================================

  perform 1
  from public.teachers t
  where t.id = p_teacher_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;


  select
    p.branch_id,
    p.role,
    p.is_active
  into
    v_teacher_branch_id,
    v_teacher_role,
    v_teacher_active
  from public.profiles p
  where p.id = p_teacher_id;


  if v_teacher_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_BRANCH_REQUIRED';
  end if;


  if not v_teacher_active
     or v_teacher_role not in (
       'teacher'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_TEACHER_REQUIRED';

  end if;


  -- ==========================================================
  -- MANAGER BRANCH PERMISSION
  -- ==========================================================

  if v_actor_role =
       'manager'::public.user_role
     and not private.manager_has_branch(
       v_teacher_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- INPUT VALIDATION
  --
  -- Unlike lesson duration/work-hour candidates,
  -- blocked periods are allowed at arbitrary minute precision.
  -- Example:
  -- 14:10 ~ 15:20 may legitimately block overlapping slots.
  -- ==========================================================

  if p_starts_at is null
     or p_ends_at is null
     or p_starts_at >= p_ends_at then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_BLOCKED_PERIOD_RANGE';

  end if;


  v_normalized_reason :=
    nullif(
      btrim(
        coalesce(p_reason, '')
      ),
      ''
    );


  -- ==========================================================
  -- UPDATE TARGET
  -- ==========================================================

  if p_blocked_period_id is not null then

    select *
    into v_existing
    from public.blocked_periods bp
    where bp.id = p_blocked_period_id
    for update;


    if not found then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_BLOCKED_PERIOD_NOT_FOUND';
    end if;


    if v_existing.teacher_id <>
       p_teacher_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_BLOCKED_PERIOD_TEACHER_MISMATCH';

    end if;


    v_before :=
      jsonb_build_object(
        'id', v_existing.id,
        'teacherId', v_existing.teacher_id,
        'startsAt', v_existing.starts_at,
        'endsAt', v_existing.ends_at,
        'reason', v_existing.reason
      );


    begin

      update public.blocked_periods
      set
        starts_at = p_starts_at,
        ends_at = p_ends_at,
        reason = v_normalized_reason
      where id = p_blocked_period_id
      returning id
      into v_result_id;

    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_BLOCKED_PERIOD_OVERLAP';

    end;


  else

    v_before := null;


    begin

      insert into public.blocked_periods (
        teacher_id,
        starts_at,
        ends_at,
        reason,
        created_by
      )
      values (
        p_teacher_id,
        p_starts_at,
        p_ends_at,
        v_normalized_reason,
        v_actor_id
      )
      returning id
      into v_result_id;

    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_BLOCKED_PERIOD_OVERLAP';

    end;

  end if;


  -- ==========================================================
  -- EXISTING LESSON WARNING
  --
  -- Existing scheduled lessons are NOT changed.
  -- We only report how many overlap this new unavailable period.
  -- ==========================================================

  select count(*)::integer
  into v_lesson_overlap_count
  from public.lessons l
  where l.teacher_id = p_teacher_id

    and l.status =
        'scheduled'::public.lesson_status

    and tstzrange(
          l.starts_at,
          l.ends_at,
          '[)'
        )
        &&
        tstzrange(
          p_starts_at,
          p_ends_at,
          '[)'
        );


  v_after :=
    jsonb_build_object(
      'id', v_result_id,
      'teacherId', p_teacher_id,
      'startsAt', p_starts_at,
      'endsAt', p_ends_at,
      'reason', v_normalized_reason
    );


  -- ==========================================================
  -- AUDIT
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    actor_id,
    details
  )
  values (
    p_teacher_id,
    v_teacher_branch_id,

    case
      when p_blocked_period_id is null
        then 'TEACHER_BLOCKED_PERIOD_CREATED'
      else 'TEACHER_BLOCKED_PERIOD_UPDATED'
    end,

    v_actor_id,

    jsonb_build_object(
      'before', v_before,
      'after', v_after,
      'scheduledLessonOverlapCount',
        v_lesson_overlap_count
    )
  );


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'blockedPeriodId',
      v_result_id,

    'teacherId',
      p_teacher_id,

    'branchId',
      v_teacher_branch_id,

    'scheduledLessonOverlapCount',
      v_lesson_overlap_count,

    'warningCodes',
      case
        when v_lesson_overlap_count > 0
        then jsonb_build_array(
          'FORESTRING_BLOCKED_PERIOD_HAS_EXISTING_LESSONS'
        )
        else '[]'::jsonb
      end
  );

end;
$$;


-- ============================================================
-- DELETE BLOCKED PERIOD
-- ============================================================

create or replace function public.delete_teacher_blocked_period(
  p_blocked_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_existing public.blocked_periods%rowtype;

  v_teacher_branch_id uuid;

  v_before jsonb;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id := auth.uid();


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


  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';

  end if;


  -- ==========================================================
  -- LOCK TARGET
  -- ==========================================================

  select *
  into v_existing
  from public.blocked_periods bp
  where bp.id = p_blocked_period_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BLOCKED_PERIOD_NOT_FOUND';
  end if;


  select p.branch_id
  into v_teacher_branch_id
  from public.profiles p
  where p.id = v_existing.teacher_id;


  if v_teacher_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- MANAGER BRANCH PERMISSION
  -- ==========================================================

  if v_actor_role =
       'manager'::public.user_role
     and not private.manager_has_branch(
       v_teacher_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- SNAPSHOT + DELETE
  -- ==========================================================

  v_before :=
    jsonb_build_object(
      'id', v_existing.id,
      'teacherId', v_existing.teacher_id,
      'startsAt', v_existing.starts_at,
      'endsAt', v_existing.ends_at,
      'reason', v_existing.reason
    );


  delete from public.blocked_periods
  where id = p_blocked_period_id;


  -- ==========================================================
  -- AUDIT
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    actor_id,
    details
  )
  values (
    v_existing.teacher_id,
    v_teacher_branch_id,
    'TEACHER_BLOCKED_PERIOD_DELETED',
    v_actor_id,
    jsonb_build_object(
      'before', v_before
    )
  );


  return jsonb_build_object(
    'blockedPeriodId',
      p_blocked_period_id,

    'teacherId',
      v_existing.teacher_id,

    'branchId',
      v_teacher_branch_id,

    'deleted',
      true
  );

end;
$$;


-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on function public.upsert_teacher_blocked_period(
  uuid,
  timestamptz,
  timestamptz,
  text,
  uuid
)
from public, anon;


grant execute
on function public.upsert_teacher_blocked_period(
  uuid,
  timestamptz,
  timestamptz,
  text,
  uuid
)
to authenticated;


revoke all
on function public.delete_teacher_blocked_period(
  uuid
)
from public, anon;


grant execute
on function public.delete_teacher_blocked_period(
  uuid
)
to authenticated;


comment on function public.upsert_teacher_blocked_period(
  uuid,
  timestamptz,
  timestamptz,
  text,
  uuid
) is
  'Creates or updates one teacher blocked period. Existing lessons are preserved and overlapping scheduled lessons are returned as a warning.';


comment on function public.delete_teacher_blocked_period(
  uuid
) is
  'Deletes one current teacher blocked period while preserving the change in audit_events.';