create or replace function private.finalize_due_staff_departures()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_today date;
  v_staff record;
  v_blockers jsonb;

  v_attempted_count integer := 0;
  v_finalized_count integer := 0;
  v_unchanged_count integer := 0;
  v_blocked_count integer := 0;
  v_failed_count integer := 0;

  v_error_state text;
  v_error_message text;
begin
  if session_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'FORESTRING_SYSTEM_STAFF_DEPARTURE_FORBIDDEN';
  end if;

  v_today := (
    pg_catalog.now()
    at time zone 'Asia/Seoul'
  )::date;

  for v_staff in
    select
      p.id,
      p.branch_id,
      p.role,
      p.is_active,
      t.withdrawal_date
    from public.profiles p
    join public.teachers t
      on t.id = p.id
    where p.role in (
        'teacher'::public.user_role,
        'manager'::public.user_role
      )
      and p.is_active = true
      and t.withdrawal_date is not null
      and t.withdrawal_date <= v_today
    order by t.withdrawal_date, p.id
    for update of p, t skip locked
  loop
    v_attempted_count := v_attempted_count + 1;

    begin
      if not v_staff.is_active
         or v_staff.withdrawal_date is null
         or v_staff.withdrawal_date > v_today then
        v_unchanged_count := v_unchanged_count + 1;
        continue;
      end if;

      v_blockers := private.staff_departure_blocker_summary(
        v_staff.id,
        v_staff.withdrawal_date
      );

      if coalesce(
           (v_blockers ->> 'canFinalize')::boolean,
           false
         ) <> true then
        v_blocked_count := v_blocked_count + 1;
        continue;
      end if;

      update public.profiles
      set is_active = false
      where id = v_staff.id
        and is_active = true;

      if not found then
        v_unchanged_count := v_unchanged_count + 1;
        continue;
      end if;

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
        v_staff.id,
        v_staff.branch_id,
        null,
        'STAFF_DEPARTURE_FINALIZED',
        v_staff.withdrawal_date,
        null,
        jsonb_build_object(
          'executionSource', 'system_cron',
          'role', v_staff.role,
          'withdrawalDate', v_staff.withdrawal_date
        )
      );

      v_finalized_count := v_finalized_count + 1;

    exception
      when others then
        get stacked diagnostics
          v_error_state = returned_sqlstate,
          v_error_message = message_text;

        v_failed_count := v_failed_count + 1;

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
          v_staff.id,
          v_staff.branch_id,
          null,
          'STAFF_DEPARTURE_AUTO_FAILED',
          v_staff.withdrawal_date,
          null,
          jsonb_build_object(
            'executionSource', 'system_cron',
            'sqlState', v_error_state,
            'message', v_error_message
          )
        );

        raise warning
          'Automatic staff departure failed for %: [%] %',
          v_staff.id,
          v_error_state,
          v_error_message;
    end;
  end loop;

  return jsonb_build_object(
    'runDateKst', v_today,
    'attemptedCount', v_attempted_count,
    'finalizedCount', v_finalized_count,
    'unchangedCount', v_unchanged_count,
    'blockedCount', v_blocked_count,
    'failedCount', v_failed_count
  );
end;
$function$;

revoke all
on function private.finalize_due_staff_departures()
from public, anon, authenticated, service_role;

grant execute
on function private.finalize_due_staff_departures()
to postgres;

comment on function private.finalize_due_staff_departures() is
  'Postgres-only cron worker that finalizes due staff departures when no assignments, recurring series, or scheduled lessons remain. Blocked staff stay active and per-staff failures are isolated.';

select cron.schedule(
  'forestring-finalize-due-staff-departures',
  '10 15 * * *',
  $cron$
    select private.finalize_due_staff_departures();
  $cron$
);
