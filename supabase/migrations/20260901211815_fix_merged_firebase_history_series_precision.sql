create or replace function private.import_merged_firebase_history_text(p_payload text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_line text;
  v_parts text[];
  v_firebase_id text;
  v_old_legacy text;
  v_teacher_legacy text;
  v_starts timestamptz;
  v_duration integer;
  v_type public.lesson_type;
  v_status public.lesson_status;
  v_canceled_at timestamptz;
  v_student uuid;
  v_teacher uuid;
  v_branch uuid;
  v_withdrawal date;
  v_lesson uuid;
  v_series uuid;
  v_ns constant uuid := '9115f775-37e5-5b5e-9167-71b0be32b2ab'::uuid;
  v_inserted integer := 0;
  v_duplicate_skipped integer := 0;
  v_cutoff_skipped integer := 0;
  v_failed integer := 0;
  v_failures jsonb := '[]'::jsonb;
  v_state text;
  v_message text;
begin
  if session_user <> 'postgres' then
    raise exception using errcode='42501', message='FORESTRING_MERGED_HISTORY_IMPORT_FORBIDDEN';
  end if;

  perform pg_catalog.set_config('forestring.archive_import','on',true);

  for v_line in
    select x from regexp_split_to_table(p_payload, E'\n') as x where btrim(x) <> ''
  loop
    begin
      v_parts := string_to_array(v_line, '|');
      if array_length(v_parts, 1) <> 8 then
        raise exception using errcode='22023', message='FORESTRING_MERGED_HISTORY_LINE_INVALID', detail=v_line;
      end if;

      v_firebase_id := v_parts[1];
      v_old_legacy := v_parts[2];
      v_teacher_legacy := v_parts[3];
      v_starts := v_parts[4]::timestamptz;
      v_duration := v_parts[5]::integer;
      v_type := v_parts[6]::public.lesson_type;
      v_status := v_parts[7]::public.lesson_status;
      v_canceled_at := nullif(v_parts[8], '')::timestamptz;

      if v_type not in ('regular'::public.lesson_type, 'makeup'::public.lesson_type) then
        raise exception using errcode='22023', message='FORESTRING_MERGED_HISTORY_TYPE_INVALID';
      end if;
      if v_status = 'canceled'::public.lesson_status and v_canceled_at is null then
        raise exception using errcode='23514', message='FORESTRING_MERGED_HISTORY_CANCELED_AT_REQUIRED';
      end if;
      if v_status = 'scheduled'::public.lesson_status then
        v_canceled_at := null;
      end if;

      select sla.student_id, cp.branch_id,
             nullif(a.student_snapshot->>'withdrawal_date','')::date
      into v_student, v_branch, v_withdrawal
      from private.student_legacy_aliases sla
      join public.profiles cp on cp.id = sla.student_id
      join lateral (
        select mia.student_snapshot
        from private.student_identity_merge_audit mia
        where mia.old_legacy_id = v_old_legacy
          and mia.canonical_student_id = sla.student_id
        order by mia.merged_at desc
        limit 1
      ) a on true
      where sla.alias_legacy_id = v_old_legacy;

      if v_student is null or v_withdrawal is null then
        raise exception using errcode='23503', message='FORESTRING_MERGED_HISTORY_ALIAS_NOT_FOUND', detail=v_old_legacy;
      end if;

      if (v_starts at time zone 'Asia/Seoul')::date >= v_withdrawal
         or (v_starts at time zone 'Asia/Seoul')::date >= (pg_catalog.now() at time zone 'Asia/Seoul')::date then
        v_cutoff_skipped := v_cutoff_skipped + 1;
        continue;
      end if;

      select p.id into v_teacher
      from public.profiles p
      join public.teachers t on t.id = p.id
      where p.legacy_id = v_teacher_legacy;
      if v_teacher is null then
        raise exception using errcode='23503', message='FORESTRING_MERGED_HISTORY_TEACHER_NOT_FOUND', detail=v_teacher_legacy;
      end if;

      if exists (
        select 1
        from public.lessons l
        where l.student_id = v_student
          and l.starts_at = v_starts
          and l.duration_minutes = v_duration
          and l.lesson_type = v_type
      ) then
        v_duplicate_skipped := v_duplicate_skipped + 1;
        continue;
      end if;

      v_lesson := extensions.uuid_generate_v5(v_ns, 'merged-history:lesson:' || v_firebase_id);
      v_series := case when v_type = 'regular'::public.lesson_type
                       then extensions.uuid_generate_v5(v_ns, 'merged-history:series:' || v_firebase_id)
                       else null end;

      if exists (select 1 from public.lessons where id = v_lesson) then
        v_duplicate_skipped := v_duplicate_skipped + 1;
        continue;
      end if;

      if v_type = 'regular'::public.lesson_type then
        insert into public.lesson_series(
          id, student_id, teacher_id, weekday, start_time, duration_minutes,
          effective_from, effective_until, legacy_code, branch_id, schedule_slot_id
        ) values (
          v_series, v_student, v_teacher,
          extract(isodow from (v_starts at time zone 'Asia/Seoul'))::smallint,
          date_trunc('minute', v_starts at time zone 'Asia/Seoul')::time,
          v_duration,
          (v_starts at time zone 'Asia/Seoul')::date,
          (v_starts at time zone 'Asia/Seoul')::date,
          null, v_branch, null
        ) on conflict (id) do nothing;
      end if;

      insert into public.lessons(
        id, series_id, student_id, teacher_id, occurrence_at, starts_at,
        duration_minutes, lesson_type, status, rescheduled_by, canceled_by,
        canceled_at, cancellation_reason, branch_id, lesson_right_id,
        manual_makeup_right_id
      ) values (
        v_lesson, v_series, v_student, v_teacher,
        case when v_type = 'regular'::public.lesson_type then v_starts else null end,
        v_starts, v_duration, v_type, v_status, null, null,
        v_canceled_at,
        case when v_status = 'canceled'::public.lesson_status
             then 'firebase_merged_history_recovery' else null end,
        v_branch, null, null
      );

      v_inserted := v_inserted + 1;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
      v_failed := v_failed + 1;
      v_failures := v_failures || jsonb_build_array(jsonb_build_object(
        'firebaseId', coalesce(v_firebase_id,''),
        'studentLegacy', coalesce(v_old_legacy,''),
        'startsAt', coalesce(case when v_parts is null then null else v_parts[4] end,''),
        'sqlState', v_state,
        'message', v_message
      ));
    end;
  end loop;

  return jsonb_build_object(
    'inserted', v_inserted,
    'duplicateSkipped', v_duplicate_skipped,
    'cutoffSkipped', v_cutoff_skipped,
    'failed', v_failed,
    'failures', v_failures
  );
end;
$function$;

revoke all on function private.import_merged_firebase_history_text(text) from public, anon, authenticated;