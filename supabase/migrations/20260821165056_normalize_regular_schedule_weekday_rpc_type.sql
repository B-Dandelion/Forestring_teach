-- ============================================================
-- Forestring v3
-- Normalize public RPC weekday input to PostgreSQL integer.
--
-- Flutter/Dart uses int, while the internal weekday columns may
-- remain smallint.
-- ============================================================

drop function if exists public.change_regular_schedule(
  uuid,
  uuid,
  smallint,
  time,
  integer,
  date
);

-- ============================================================
-- Forestring v3
-- Change versioned regular schedule rule
-- and reconcile untouched future canonical lessons.
--
-- Immutable logical identity:
--   regular_schedule_slots.id
--
-- Versioned default rule:
--   lesson_series
--
-- Existing canonical future lessons:
--
--   untouched/default-following
--     -> reconciled
--
--   past
--   canceled
--   individually moved/rebooked
--   cancellation-history lesson
--     -> preserved
-- ============================================================


create or replace function public.change_regular_schedule(
  p_schedule_slot_id uuid,
  p_teacher_id uuid,
  p_weekday integer,
  p_start_time time,
  p_duration_minutes integer,
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

  v_slot public.regular_schedule_slots%rowtype;
  v_old_series public.lesson_series%rowtype;

  v_student_branch_id uuid;
  v_student_status public.student_status;
  v_student_withdrawal_date date;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_new_series_id uuid;
  v_new_effective_until date;

  v_end_minutes integer;
  v_end_time time;

  v_lesson record;

  v_current_semester_id uuid;
  v_ordinal integer := 0;

  v_semester_start date;
  v_semester_end date;

  v_new_date date;
  v_new_starts_at timestamptz;
  v_new_ends_at timestamptz;

  v_reconciled_count integer := 0;

  v_in_place boolean := false;
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


  if v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role,
    'teacher'::public.user_role
  ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';

  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- 2. INPUT
  -- ==========================================================

  if p_effective_on is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_EFFECTIVE_DATE_REQUIRED';
  end if;


  -- Historical schedule rules are never rewritten retroactively.
  if p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;


  if p_weekday not between 1 and 7 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_WEEKDAY';
  end if;


  if p_start_time is null
     or
     extract(second from p_start_time) <> 0
     or
     mod(
       extract(minute from p_start_time)::integer,
       15
     ) <> 0 then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';

  end if;


  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(
          p_duration_minutes,
          15
        ) <> 0 then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_REGULAR_DURATION';

  end if;


  v_end_minutes :=
      extract(hour from p_start_time)::integer * 60
    + extract(minute from p_start_time)::integer
    + p_duration_minutes;


  if v_end_minutes > 1440 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_LESSON_CROSSES_MIDNIGHT';
  end if;


  v_end_time :=
    (
      p_start_time
      + pg_catalog.make_interval(
          mins => p_duration_minutes
        )
    )::time;


  -- ==========================================================
  -- 3. LOCK LOGICAL SLOT
  -- ==========================================================

  select *
  into v_slot

  from public.regular_schedule_slots rs

  where rs.id =
        p_schedule_slot_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';
  end if;


  if p_effective_on <
     v_slot.starts_on then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_CHANGE_BEFORE_SLOT_START';

  end if;


  if v_slot.ends_on is not null
     and p_effective_on >
         v_slot.ends_on then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_CHANGE_AFTER_SLOT_END';

  end if;


  -- ==========================================================
  -- 4. STUDENT
  -- ==========================================================

  select
    p.branch_id,
    s.status,
    s.withdrawal_date

  into
    v_student_branch_id,
    v_student_status,
    v_student_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        v_slot.student_id

    and p.is_active = true;


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


  if v_student_branch_id is distinct from
     v_slot.branch_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_SLOT_BRANCH_MISMATCH';

  end if;


  if v_student_withdrawal_date is not null
     and p_effective_on >=
         v_student_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SCHEDULE_AFTER_STUDENT_WITHDRAWAL';

  end if;


  -- ==========================================================
  -- 5. ACTOR BRANCH / TEACHER AUTHORITY
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_slot.branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- A normal teacher may edit only a schedule that remains
  -- assigned to themselves.
  if v_actor_role =
     'teacher'::public.user_role
     and p_teacher_id <>
         v_actor_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_TEACHER_CANNOT_REASSIGN_STUDENT';

  end if;


  -- ==========================================================
  -- 6. TARGET TEACHER
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

  where t.id =
        p_teacher_id;


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
     v_slot.branch_id then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_MISMATCH';

  end if;


  if v_teacher_withdrawal_date is not null
     and p_effective_on >=
         v_teacher_withdrawal_date then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SCHEDULE_AFTER_TEACHER_WITHDRAWAL';

  end if;


  -- ==========================================================
  -- 7. ASSIGNMENT MUST AGREE WITH DEFAULT TEACHER
  --
  -- teacher_student_assignments remains authoritative for
  -- who owns this student on a given date.
  -- ==========================================================

  if not exists (
    select 1

    from public.teacher_student_assignments a

    where a.student_id =
          v_slot.student_id

      and a.teacher_id =
          p_teacher_id

      and a.branch_id =
          v_slot.branch_id

      and a.starts_on <=
          p_effective_on

      and (
        a.ends_on is null
        or a.ends_on >=
           p_effective_on
      )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH';

  end if;


  -- ==========================================================
  -- 8. NORMAL WEEKLY WORK HOURS
  --
  -- Recurring defaults must fit normal work hours strictly.
  -- ==========================================================

  if not exists (
    select 1

    from public.teacher_work_hours wh

    where wh.teacher_id =
          p_teacher_id

      and wh.weekday =
          p_weekday

      and wh.start_time <=
          p_start_time

      and wh.end_time >=
          v_end_time
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS';

  end if;


  -- ==========================================================
  -- 9. CURRENT SERIES VERSION
  -- ==========================================================

  select *
  into v_old_series

  from public.lesson_series ls

  where ls.schedule_slot_id =
        v_slot.id

    and ls.student_id =
        v_slot.student_id

    and ls.branch_id =
        v_slot.branch_id

    and ls.effective_from <=
        p_effective_on

    and (
      ls.effective_until is null
      or ls.effective_until >=
         p_effective_on
    )

  order by ls.effective_from desc

  limit 1

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_SERIES_NOT_FOUND_FOR_EFFECTIVE_DATE';

  end if;


  -- We intentionally do not silently overwrite another
  -- already-planned future version.
  if exists (
    select 1

    from public.lesson_series ls

    where ls.schedule_slot_id =
          v_slot.id

      and ls.effective_from >
          p_effective_on
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_REGULAR_SCHEDULE_FUTURE_VERSION_EXISTS';

  end if;


  -- ==========================================================
  -- 10. NO-OP
  -- ==========================================================

  if v_old_series.teacher_id =
       p_teacher_id

     and v_old_series.weekday =
         p_weekday

     and v_old_series.start_time =
         p_start_time

     and v_old_series.duration_minutes =
         p_duration_minutes then

    return jsonb_build_object(
      'changed', false,
      'scheduleSlotId', v_slot.id,
      'seriesId', v_old_series.id,
      'reconciledLessonCount', 0
    );

  end if;


  v_new_effective_until :=
    v_old_series.effective_until;


  -- ==========================================================
  -- 11. VERSION THE DEFAULT RULE
  --
  -- If this version itself starts exactly on the requested
  -- effective date, it is still an un-backdated current/future
  -- version and may be corrected in-place.
  --
  -- Otherwise close old version and append a new one.
  -- ==========================================================

  if v_old_series.effective_from =
     p_effective_on then

    begin

      update public.lesson_series
      set
        teacher_id =
          p_teacher_id,

        weekday =
          p_weekday,

        start_time =
          p_start_time,

        duration_minutes =
          p_duration_minutes

      where id =
            v_old_series.id

      returning id
      into v_new_series_id;


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SERIES_TIME_CONFLICT';

    end;


    v_in_place :=
      true;


  else

    update public.lesson_series
    set
      effective_until =
        p_effective_on - 1

    where id =
          v_old_series.id;


    begin

      insert into public.lesson_series (
        student_id,
        teacher_id,
        weekday,
        start_time,
        duration_minutes,
        effective_from,
        effective_until,
        branch_id,
        schedule_slot_id
      )
      values (
        v_slot.student_id,
        p_teacher_id,
        p_weekday,
        p_start_time,
        p_duration_minutes,
        p_effective_on,
        v_new_effective_until,
        v_slot.branch_id,
        v_slot.id
      )

      returning id
      into v_new_series_id;


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SERIES_TIME_CONFLICT';

    end;

  end if;


  -- ==========================================================
  -- 12. RECONCILE DEFAULT-FOLLOWING FUTURE LESSONS
  --
  -- INCLUDED:
  --   regular right
  --   reserved
  --   scheduled lesson
  --   occurrence >= effective_on
  --   actual lesson still in future
  --   rescheduled_by IS NULL
  --   no cancellation history
  --
  -- EXCLUDED / PRESERVED:
  --   past
  --   canceled
  --   individually moved
  --   canceled + rebooked
  --
  -- Existing occurrence_at remains unchanged.
  -- Existing series_id also remains historical provenance.
  -- ==========================================================

  v_current_semester_id :=
    null;

  v_ordinal :=
    0;


  for v_lesson in

    select
      l.id as lesson_id,
      l.lesson_right_id,
      l.occurrence_at,
      l.starts_at,

      r.source_semester_id,

      -- Preserve the original entitlement position even when
      -- an earlier future lesson is canceled or individually
      -- rescheduled.
      --
      -- Example:
      --
      -- #1 canceled
      -- #2 untouched
      -- #3 individually moved
      -- #4 untouched
      --
      -- Reconciliation ordinals must remain:
      -- #2 -> 2
      -- #4 -> 4
      --
      -- rather than compressing them to 1 and 2.
      (
        select count(*)::integer

        from public.lessons position_lesson

        join public.lesson_rights position_right
          on position_right.id =
             position_lesson.lesson_right_id

        where position_right.student_id =
              v_slot.student_id

          and position_right.branch_id =
              v_slot.branch_id

          and position_right.schedule_slot_id =
              v_slot.id

          and position_right.origin =
              'regular_base'::public.lesson_right_origin

          and position_right.source_semester_id =
              r.source_semester_id

          and position_lesson.lesson_type =
              'regular'::public.lesson_type

          and position_lesson.occurrence_at
              is not null

          and (
            position_lesson.occurrence_at
            at time zone 'Asia/Seoul'
          )::date >=
              p_effective_on

          and (
            position_lesson.occurrence_at <
              l.occurrence_at

            or (
              position_lesson.occurrence_at =
                l.occurrence_at

              and position_lesson.id <=
                  l.id
            )
          )
      ) as reconcile_ordinal

    from public.lessons l

    join public.lesson_rights r
      on r.id =
         l.lesson_right_id

    where r.student_id =
          v_slot.student_id

      and r.branch_id =
          v_slot.branch_id

      and r.schedule_slot_id =
          v_slot.id

      and r.origin =
          'regular_base'::public.lesson_right_origin

      and r.status =
          'reserved'::public.lesson_right_status

      and l.lesson_type =
          'regular'::public.lesson_type

      and l.status =
          'scheduled'::public.lesson_status

      and l.rescheduled_by is null

      and l.occurrence_at is not null

      and (
        l.occurrence_at
        at time zone 'Asia/Seoul'
      )::date >=
          p_effective_on

      and l.starts_at >
          pg_catalog.now()

      and not exists (
        select 1

        from public.lesson_cancellation_events ce

        where ce.lesson_right_id =
              r.id
      )

    order by
      r.source_semester_id,
      l.occurrence_at,
      l.id

  loop

    -- --------------------------------------------------------
    -- New semester bucket -> reset ordinal.
    -- --------------------------------------------------------

    if v_current_semester_id is distinct from
       v_lesson.source_semester_id then

      v_current_semester_id :=
        v_lesson.source_semester_id;


      select
        e.starts_on,
        e.ends_on

      into
        v_semester_start,
        v_semester_end

      from private.get_effective_semester_bounds(
        v_slot.branch_id,
        v_current_semester_id
      ) e;


      if not found then
        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_RECONCILIATION_SEMESTER_NOT_FOUND';
      end if;

    end if;


    -- Do NOT count only the lessons being mutated.
    --
    -- Canceled / individually moved / previously rebooked
    -- occurrences keep occupying their original ordinal
    -- position so later default-following lessons never slide
    -- forward into those positions.
    v_ordinal :=
      v_lesson.reconcile_ordinal;


    -- --------------------------------------------------------
    -- Map Nth untouched entitlement in this semester to the
    -- Nth valid occurrence under the NEW recurring rule.
    --
    -- Instructional break weeks are removed.
    --
    -- occurrence_at itself is NOT changed.
    -- --------------------------------------------------------

    select candidate.lesson_date
    into v_new_date

    from (
      select
        d::date as lesson_date

      from pg_catalog.generate_series(
        greatest(
          v_semester_start,
          p_effective_on
        )::timestamp,

        least(
          v_semester_end,
          coalesce(
            v_new_effective_until,
            v_semester_end
          )
        )::timestamp,

        interval '1 day'
      ) d

      where extract(
              isodow
              from d::date
            )::smallint =
            p_weekday

        and d::date >=
            v_slot.starts_on

        and (
          v_slot.ends_on is null
          or d::date <=
             v_slot.ends_on
        )

        and not exists (
          select 1

          from public.closure_periods cp

          where cp.branch_id =
                v_slot.branch_id

            and cp.semester_id =
                v_current_semester_id

            and cp.closure_kind =
                'instructional_break'
                  ::public.closure_kind

            and d::date between
                cp.starts_on
                and cp.ends_on
        )

      order by d::date

      offset v_ordinal - 1
      limit 1
    ) candidate;


    if v_new_date is null then
      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH',
        detail =
          'semester_id=' ||
          v_current_semester_id::text ||
          ', ordinal=' ||
          v_ordinal::text;
    end if;


    v_new_starts_at :=
      (
        v_new_date
        + p_start_time
      ) at time zone 'Asia/Seoul';


    v_new_ends_at :=
      v_new_starts_at
      + pg_catalog.make_interval(
          mins => p_duration_minutes
        );


    -- --------------------------------------------------------
    -- Assignment is checked AGAIN on the actual candidate date.
    --
    -- This catches a separately planned future teacher change.
    -- --------------------------------------------------------

    if not exists (
      select 1

      from public.teacher_student_assignments a

      where a.student_id =
            v_slot.student_id

        and a.teacher_id =
            p_teacher_id

        and a.branch_id =
            v_slot.branch_id

        and a.starts_on <=
            v_new_date

        and (
          a.ends_on is null
          or a.ends_on >=
             v_new_date
        )
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RECONCILIATION_ASSIGNMENT_MISMATCH',
        detail =
          'date=' ||
          v_new_date::text;

    end if;


    -- --------------------------------------------------------
    -- Ordinary branch closure is a hard conflict.
    -- --------------------------------------------------------

    if exists (
      select 1

      from public.closure_periods cp

      where cp.branch_id =
            v_slot.branch_id

        and cp.closure_kind =
            'ordinary'::public.closure_kind

        and v_new_date between
            cp.starts_on
            and cp.ends_on
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RECONCILIATION_ON_CLOSURE',
        detail =
          'date=' ||
          v_new_date::text;

    end if;


    -- --------------------------------------------------------
    -- One-off teacher blocked period is also hard.
    -- --------------------------------------------------------

    if exists (
      select 1

      from public.blocked_periods bp

      where bp.teacher_id =
            p_teacher_id

        and tstzrange(
              bp.starts_at,
              bp.ends_at,
              '[)'
            )
            &&
            tstzrange(
              v_new_starts_at,
              v_new_ends_at,
              '[)'
            )
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RECONCILIATION_BLOCKED',
        detail =
          'starts_at=' ||
          v_new_starts_at::text;

    end if;


    -- --------------------------------------------------------
    -- Update entitlement default duration.
    --
    -- This right is guaranteed untouched:
    --   reserved
    --   no cancellation history
    --
    -- If it is canceled later, the newly configured duration
    -- is what gets restored by book_lesson_right().
    -- --------------------------------------------------------

    update public.lesson_rights
    set
      duration_minutes =
        p_duration_minutes

    where id =
          v_lesson.lesson_right_id;


    -- --------------------------------------------------------
    -- Update actual default-following lesson.
    --
    -- KEEP:
    --   id
    --   right
    --   series provenance
    --   occurrence_at
    --
    -- CHANGE:
    --   actual teacher
    --   actual start
    --   actual duration
    --
    -- rescheduled_by remains NULL, meaning this lesson still
    -- follows the regular default rather than an individual
    -- override.
    -- --------------------------------------------------------

    begin

      update public.lessons
      set
        teacher_id =
          p_teacher_id,

        starts_at =
          v_new_starts_at,

        duration_minutes =
          p_duration_minutes

      where id =
            v_lesson.lesson_id;


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT',
          detail =
            'lesson_id=' ||
            v_lesson.lesson_id::text ||
            ', starts_at=' ||
            v_new_starts_at::text;

    end;


    v_reconciled_count :=
      v_reconciled_count + 1;

  end loop;


  -- ==========================================================
  -- 13. AUDIT
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
    v_slot.student_id,
    v_slot.branch_id,
    null,
    'REGULAR_SCHEDULE_CHANGED',
    p_effective_on,
    v_actor_id,

    jsonb_build_object(
      'scheduleSlotId',
        v_slot.id,

      'previousSeriesId',
        v_old_series.id,

      'newSeriesId',
        v_new_series_id,

      'seriesUpdatedInPlace',
        v_in_place,

      'before',
        jsonb_build_object(
          'teacherId',
            v_old_series.teacher_id,

          'weekday',
            v_old_series.weekday,

          'startTime',
            v_old_series.start_time,

          'durationMinutes',
            v_old_series.duration_minutes
        ),

      'after',
        jsonb_build_object(
          'teacherId',
            p_teacher_id,

          'weekday',
            p_weekday,

          'startTime',
            p_start_time,

          'durationMinutes',
            p_duration_minutes
        ),

      'reconciledLessonCount',
        v_reconciled_count
    )
  );


  -- ==========================================================
  -- 14. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'scheduleSlotId',
      v_slot.id,

    'previousSeriesId',
      v_old_series.id,

    'newSeriesId',
      v_new_series_id,

    'seriesUpdatedInPlace',
      v_in_place,

    'effectiveOn',
      p_effective_on,

    'teacherId',
      p_teacher_id,

    'weekday',
      p_weekday,

    'startTime',
      p_start_time,

    'durationMinutes',
      p_duration_minutes,

    'reconciledLessonCount',
      v_reconciled_count
  );

end;
$$;


-- ============================================================
-- PRIVILEGES
-- ============================================================

revoke all
on function public.change_regular_schedule(
  uuid,
  uuid,
  integer,
  time,
  integer,
  date
)
from public, anon;


grant execute
on function public.change_regular_schedule(
  uuid,
  uuid,
  integer,
  time,
  integer,
  date
)
to authenticated;


comment on function public.change_regular_schedule(
  uuid,
  uuid,
  integer,
  time,
  integer,
  date
) is
  'Versions one logical regular schedule rule from an effective date and atomically reconciles only untouched future reserved regular lessons. Past, canceled, individually rescheduled/rebooked lessons and lessons with cancellation history remain unchanged; canonical lesson/right/occurrence identities are preserved.';