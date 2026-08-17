-- ============================================================
-- Forestring v3 - Harden authentication rate limiting
-- ============================================================

create or replace function public.auth_record_login_failure(
  p_bucket_key text,
  p_window_seconds integer,
  p_max_attempts integer,
  p_lock_seconds integer
)
returns table (
  failed_attempts integer,
  window_started_at timestamptz,
  locked_until timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_row private.login_rate_limits%rowtype;
  v_failed integer;
  v_window_started timestamptz;
  v_locked_until timestamptz;
begin
  if p_window_seconds <= 0
     or p_max_attempts <= 0
     or p_lock_seconds <= 0 then
    raise exception 'Rate-limit arguments must be positive.';
  end if;

  insert into private.login_rate_limits (
    bucket_key,
    failed_attempts,
    window_started_at,
    locked_until
  )
  values (
    p_bucket_key,
    0,
    v_now,
    null
  )
  on conflict (bucket_key) do nothing;

  select *
  into v_row
  from private.login_rate_limits
  where bucket_key = p_bucket_key
  for update;

  if v_row.locked_until is not null
     and v_row.locked_until > v_now then
    return query
    select
      v_row.failed_attempts,
      v_row.window_started_at,
      v_row.locked_until;

    return;
  end if;

  if v_now >= (
    v_row.window_started_at
    + pg_catalog.make_interval(secs => p_window_seconds)
  ) then
    v_failed := 1;
    v_window_started := v_now;
  else
    v_failed := v_row.failed_attempts + 1;
    v_window_started := v_row.window_started_at;
  end if;

  if v_failed >= p_max_attempts then
    v_locked_until :=
      v_now + pg_catalog.make_interval(secs => p_lock_seconds);
  else
    v_locked_until := null;
  end if;

  update private.login_rate_limits
  set
    failed_attempts = v_failed,
    window_started_at = v_window_started,
    locked_until = v_locked_until
  where bucket_key = p_bucket_key;

  return query
  select
    v_failed,
    v_window_started,
    v_locked_until;
end;
$$;

revoke all
on function public.auth_record_login_failure(
  text,
  integer,
  integer,
  integer
)
from public, anon, authenticated;

grant execute
on function public.auth_record_login_failure(
  text,
  integer,
  integer,
  integer
)
to service_role;
