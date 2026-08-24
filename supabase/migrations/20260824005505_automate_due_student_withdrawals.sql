-- ============================================================
-- Forestring v3
-- Automatically finalize due student withdrawals.
--
-- Existing public.finalize_student_withdrawal(uuid) remains the
-- single authoritative cleanup path. This migration adds a
-- postgres-only system execution path and schedules it for
-- 00:05 KST every day (15:05 UTC).
-- ============================================================


create extension if not exists pg_cron
with schema pg_catalog;


grant usage on schema cron
to postgres;


grant all privileges
on all tables in schema cron
to postgres;


-- ============================================================
-- SYSTEM EXECUTION PATH
--
-- The app still needs an authenticated master/manager. Only a
-- postgres-owned cron connection with the transaction-local
-- marker below may call the same RPC without auth.uid().
--
-- Patch the current authoritative function rather than copying
-- its withdrawal cleanup logic into a second implementation.
-- The migration fails closed if the expected function body has
-- changed, preventing an unsafe partial patch.
-- ============================================================

do $migration$
declare
  v_definition text;
  v_original_auth text := $original_auth$
  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  perform private.require_effective_actor(
    v_actor_id
  );


  select p.role
  into v_actor_role

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
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
$original_auth$;

  v_system_auth text := $system_auth$
  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    if session_user <> 'postgres'
       or pg_catalog.current_setting(
            'forestring.system_withdrawal',
            true
          ) is distinct from 'cron' then

      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_AUTH_REQUIRED';

    end if;


    -- Reuse the existing master authorization branch without
    -- attributing the automated action to a human profile.
    v_actor_role :=
      'master'::public.user_role;

  else

    perform private.require_effective_actor(
      v_actor_id
    );


    select p.role
    into v_actor_role

    from public.profiles p

    where p.id =
          v_actor_id

      and p.is_active = true;


    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_ACTIVE_USER_REQUIRED';
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

  end if;
$system_auth$;

  v_original_audit text := $original_audit$
    jsonb_build_object(
      'withdrawalDate',
        v_withdrawal_date,
$original_audit$;

  v_system_audit text := $system_audit$
    jsonb_build_object(
      'executionSource',
        case
          when v_actor_id is null then
            'system_cron'
          else
            'staff'
        end,

      'withdrawalDate',
        v_withdrawal_date,
$system_audit$;
begin

  select pg_catalog.pg_get_functiondef(
    'public.finalize_student_withdrawal(uuid)'::regprocedure
  )
  into v_definition;


  if v_definition is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWAL_FINALIZER_NOT_FOUND';
  end if;


  if pg_catalog.strpos(
       v_definition,
       v_original_auth
     ) = 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWAL_AUTH_PATCH_MISMATCH';

  end if;


  if pg_catalog.strpos(
       v_definition,
       v_original_audit
     ) = 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWAL_AUDIT_PATCH_MISMATCH';

  end if;


  v_definition :=
    pg_catalog.replace(
      v_definition,
      v_original_auth,
      v_system_auth
    );


  v_definition :=
    pg_catalog.replace(
      v_definition,
      v_original_audit,
      v_system_audit
    );


  execute v_definition;

end;
$migration$;


-- ============================================================
-- CRON WORKER
--
-- Each student runs inside a PL/pgSQL exception subtransaction.
-- A corrupt student record therefore cannot block every other
-- due withdrawal. Failures are preserved in audit_events and
-- can still be finalized with the existing app fallback.
-- ============================================================

create or replace function
private.finalize_due_student_withdrawals()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_student record;
  v_result jsonb;

  v_attempted_count integer := 0;
  v_finalized_count integer := 0;
  v_unchanged_count integer := 0;
  v_failed_count integer := 0;

  v_error_state text;
  v_error_message text;
begin

  if session_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message =
        'FORESTRING_SYSTEM_WITHDRAWAL_FORBIDDEN';
  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  perform pg_catalog.set_config(
    'forestring.system_withdrawal',
    'cron',
    true
  );


  for v_student in
    select
      s.id,
      s.withdrawal_date,
      p.branch_id

    from public.students s

    join public.profiles p
      on p.id = s.id

    where s.status =
          'active'::public.student_status

      and s.withdrawal_date is not null

      and s.withdrawal_date <=
          v_today

    order by
      s.withdrawal_date,
      s.id
  loop

    v_attempted_count :=
      v_attempted_count + 1;


    begin

      v_result :=
        public.finalize_student_withdrawal(
          v_student.id
        );


      if coalesce(
           (v_result ->> 'changed')::boolean,
           false
         ) then

        v_finalized_count :=
          v_finalized_count + 1;

      else

        v_unchanged_count :=
          v_unchanged_count + 1;

      end if;


    exception
      when others then

        get stacked diagnostics
          v_error_state = returned_sqlstate,
          v_error_message = message_text;


        v_failed_count :=
          v_failed_count + 1;


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
          v_student.id,
          v_student.branch_id,
          null,
          'STUDENT_WITHDRAWAL_AUTO_FAILED',
          v_student.withdrawal_date,
          null,

          jsonb_build_object(
            'executionSource',
              'system_cron',

            'sqlState',
              v_error_state,

            'message',
              v_error_message
          )
        );


        raise warning
          'Automatic withdrawal failed for student %: [%] %',
          v_student.id,
          v_error_state,
          v_error_message;

    end;

  end loop;


  return jsonb_build_object(
    'runDateKst',
      v_today,

    'attemptedCount',
      v_attempted_count,

    'finalizedCount',
      v_finalized_count,

    'unchangedCount',
      v_unchanged_count,

    'failedCount',
      v_failed_count
  );

end;
$$;


revoke all
on function private.finalize_due_student_withdrawals()
from public, anon, authenticated, service_role;


grant execute
on function private.finalize_due_student_withdrawals()
to postgres;


comment on function
private.finalize_due_student_withdrawals() is
  'Postgres-only cron worker that finalizes every active student whose KST withdrawal date has arrived. It reuses public.finalize_student_withdrawal(), records system attribution, and isolates per-student failures.';


-- pg_cron uses UTC/GMT in this project.
-- 15:05 UTC = 00:05 KST on the following calendar day.
select cron.schedule(
  'forestring-finalize-due-student-withdrawals',
  '5 15 * * *',
  $cron$
    select private.finalize_due_student_withdrawals();
  $cron$
);
