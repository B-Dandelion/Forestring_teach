begin;

do $$
declare
  v_manager_id uuid;
  v_branch_id uuid;
  v_other_manager_id uuid;
  v_teacher_id uuid;

  v_segments jsonb :=
    '[
      {
        "weekday": 7,
        "startTime": "00:00",
        "endTime": "00:15"
      },
      {
        "weekday": 7,
        "startTime": "00:30",
        "endTime": "00:45"
      }
    ]'::jsonb;

  v_existing jsonb;
  v_result jsonb;

  v_before_lessons jsonb;
  v_after_lessons jsonb;

  v_before_audit_count integer;
  v_after_audit_count integer;

  v_overlap_denied boolean := false;
  v_cross_branch_denied boolean := false;
begin

  -- ==========================================================
  -- 1. SAME-BRANCH MANAGER
  -- ==========================================================

  select
    p.id,
    p.branch_id
  into
    v_manager_id,
    v_branch_id
  from public.profiles p
  join public.teachers t
    on t.id = p.id
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
  order by p.created_at
  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active manager with teacher row';
  end if;


  -- Manager himself is a valid teacher entity.
  v_teacher_id := v_manager_id;


  -- ==========================================================
  -- 2. OTHER-BRANCH MANAGER
  -- ==========================================================

  select p.id
  into v_other_manager_id
  from public.profiles p
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
    and p.branch_id <> v_branch_id
  order by p.created_at
  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 3. NORMALIZE CURRENT WORK HOURS
  --
  -- If our chosen test schedule happens to already exist,
  -- switch to another deterministic schedule so the first
  -- save is guaranteed to be a real change.
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'weekday', wh.weekday,
        'startTime', to_char(wh.start_time, 'HH24:MI'),
        'endTime', to_char(wh.end_time, 'HH24:MI')
      )
      order by
        wh.weekday,
        wh.start_time,
        wh.end_time
    ),
    '[]'::jsonb
  )
  into v_existing
  from public.teacher_work_hours wh
  where wh.teacher_id = v_teacher_id;


  if v_existing = v_segments then
    v_segments :=
      '[
        {
          "weekday": 7,
          "startTime": "01:00",
          "endTime": "01:15"
        },
        {
          "weekday": 7,
          "startTime": "01:30",
          "endTime": "01:45"
        }
      ]'::jsonb;
  end if;


  -- ==========================================================
  -- 4. SNAPSHOT EXISTING LESSONS
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'startsAt', l.starts_at,
        'endsAt', l.ends_at,
        'durationMinutes', l.duration_minutes,
        'status', l.status,
        'teacherId', l.teacher_id,
        'studentId', l.student_id
      )
      order by l.id
    ),
    '[]'::jsonb
  )
  into v_before_lessons
  from public.lessons l
  where l.teacher_id = v_teacher_id;


  select count(*)::integer
  into v_before_audit_count
  from public.audit_events a
  where a.subject_profile_id = v_teacher_id
    and a.event_type = 'TEACHER_WORK_HOURS_CHANGED';


  -- ==========================================================
  -- 5. SIMULATE SAME-BRANCH MANAGER
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 6. NORMAL REPLACEMENT MUST SUCCEED
  -- ==========================================================

  v_result :=
    public.replace_teacher_work_hours(
      v_teacher_id,
      v_segments
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: first work-hours replacement should change';
  end if;


  if (v_result ->> 'segmentCount')::integer <> 2 then
    raise exception
      'TEST_FAILED: expected 2 segments, got %',
      v_result ->> 'segmentCount';
  end if;


  -- ==========================================================
  -- 7. SAME INPUT AGAIN = NO-OP
  -- ==========================================================

  v_result :=
    public.replace_teacher_work_hours(
      v_teacher_id,
      v_segments
    );


  if (v_result ->> 'changed')::boolean <> false then
    raise exception
      'TEST_FAILED: identical save should be no-op';
  end if;


  -- ==========================================================
  -- 8. OVERLAPPING INPUT MUST FAIL
  -- ==========================================================

  begin

    perform public.replace_teacher_work_hours(
      v_teacher_id,
      '[
        {
          "weekday": 1,
          "startTime": "10:00",
          "endTime": "12:00"
        },
        {
          "weekday": 1,
          "startTime": "11:45",
          "endTime": "13:00"
        }
      ]'::jsonb
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_WORK_HOURS_OVERLAP' then

        v_overlap_denied := true;

      else
        raise;
      end if;

  end;


  if not v_overlap_denied then
    raise exception
      'TEST_FAILED: overlapping work hours were accepted';
  end if;


  -- ==========================================================
  -- 9. CROSS-BRANCH MANAGER MUST FAIL
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_other_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_other_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  begin

    perform public.replace_teacher_work_hours(
      v_teacher_id,
      '[]'::jsonb
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then

        v_cross_branch_denied := true;

      else
        raise;
      end if;

  end;


  if not v_cross_branch_denied then
    raise exception
      'TEST_FAILED: cross-branch manager was not denied';
  end if;


  -- ==========================================================
  -- 10. SAME-BRANCH MANAGER MAY CLEAR ALL HOURS
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_result :=
    public.replace_teacher_work_hours(
      v_teacher_id,
      '[]'::jsonb
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: clearing work hours should change';
  end if;


  if (v_result ->> 'segmentCount')::integer <> 0 then
    raise exception
      'TEST_FAILED: expected zero work-hour segments after clear';
  end if;


  if exists (
    select 1
    from public.teacher_work_hours wh
    where wh.teacher_id = v_teacher_id
  ) then

    raise exception
      'TEST_FAILED: work hours remain after empty replacement';

  end if;


  -- ==========================================================
  -- 11. EXACTLY TWO AUDIT EVENTS
  --
  -- first real save  -> audit
  -- identical save   -> no audit
  -- invalid overlap  -> no audit
  -- cross branch     -> no audit
  -- clear all        -> audit
  -- ==========================================================

  select count(*)::integer
  into v_after_audit_count
  from public.audit_events a
  where a.subject_profile_id = v_teacher_id
    and a.event_type = 'TEACHER_WORK_HOURS_CHANGED';


  if v_after_audit_count
     - v_before_audit_count <> 2 then

    raise exception
      'TEST_FAILED: expected 2 new audit events, got %',
      v_after_audit_count - v_before_audit_count;

  end if;


  -- ==========================================================
  -- 12. EXISTING LESSONS MUST BE UNCHANGED
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'startsAt', l.starts_at,
        'endsAt', l.ends_at,
        'durationMinutes', l.duration_minutes,
        'status', l.status,
        'teacherId', l.teacher_id,
        'studentId', l.student_id
      )
      order by l.id
    ),
    '[]'::jsonb
  )
  into v_after_lessons
  from public.lessons l
  where l.teacher_id = v_teacher_id;


  if v_before_lessons <> v_after_lessons then
    raise exception
      'TEST_FAILED: work-hour replacement mutated existing lessons';
  end if;

end;
$$;


select
  'PASS: teacher work hours / no-op / overlap / branch / zero hours / lesson preservation'
  as test_result;

rollback;
