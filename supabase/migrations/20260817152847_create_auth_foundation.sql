-- ============================================================
-- Forestring v3 - Authentication foundation
--
-- Client login UX:
--   display name + 4-digit PIN
--
-- Actual Supabase Auth identity remains hidden from the user.
--
-- Sensitive credential data lives in the private schema and is
-- never queried directly by Flutter.
-- ============================================================


-- ============================================================
-- PRIVATE SCHEMA
-- ============================================================

create schema if not exists private;

-- No direct client access.
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;


-- ============================================================
-- LOGIN CREDENTIALS
--
-- One credential row per Supabase Auth / profile identity.
--
-- login_name_normalized:
--   normalized form of the visible login name.
--
-- pin_hash:
--   slow salted hash used for final PIN verification.
--
-- pin_fingerprint:
--   deterministic HMAC-SHA256 fingerprint of the PIN,
--   computed only by the trusted server using a secret pepper.
--
-- Why both?
--
-- fingerprint:
--   allows us to enforce that the same
--   (normalized name + PIN) combination cannot exist twice.
--
-- pin_hash:
--   performs the actual slow PIN verification.
--
-- Example:
--
-- 김민지 + 1234  -> allowed
-- 김민지 + 5678  -> allowed
-- 박민지 + 1234  -> allowed
--
-- 김민지 + 1234
-- 김민지 + 1234  -> rejected
-- ============================================================

create table private.login_credentials (
  profile_id uuid primary key
    references public.profiles(id)
    on delete cascade,

  login_name_normalized text not null,

  pin_hash text not null,

  -- lowercase SHA-256 HMAC hex:
  -- exactly 64 hexadecimal characters.
  pin_fingerprint text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint login_credentials_name_not_blank
    check (
      length(btrim(login_name_normalized)) > 0
    ),

  constraint login_credentials_name_trimmed
    check (
      login_name_normalized = btrim(login_name_normalized)
    ),

  constraint login_credentials_pin_hash_not_blank
    check (
      length(btrim(pin_hash)) > 0
    ),

  constraint login_credentials_fingerprint_format
    check (
      pin_fingerprint ~ '^[0-9a-f]{64}$'
    ),

  constraint login_credentials_name_pin_unique
    unique (
      login_name_normalized,
      pin_fingerprint
    )
);


create index login_credentials_name_idx
  on private.login_credentials(
    login_name_normalized
  );


create trigger login_credentials_set_updated_at
before update on private.login_credentials
for each row
execute function public.set_updated_at();


-- ============================================================
-- LOGIN RATE LIMIT STATE
--
-- We deliberately do NOT store raw IP addresses here.
--
-- Edge Function will create opaque HMAC bucket keys such as:
--   name bucket
--   IP bucket
--   name + IP bucket
--
-- This table stores only the resulting fingerprint.
-- ============================================================

create table private.login_rate_limits (
  bucket_key text primary key,

  failed_attempts integer not null default 0,

  window_started_at timestamptz not null default now(),

  locked_until timestamptz,

  updated_at timestamptz not null default now(),

  constraint login_rate_limits_bucket_format
    check (
      bucket_key ~ '^[0-9a-f]{64}$'
    ),

  constraint login_rate_limits_failed_attempts_check
    check (
      failed_attempts >= 0
    )
);


create index login_rate_limits_locked_until_idx
  on private.login_rate_limits(locked_until)
  where locked_until is not null;


create trigger login_rate_limits_set_updated_at
before update on private.login_rate_limits
for each row
execute function public.set_updated_at();


-- ============================================================
-- SERVER-ONLY CREDENTIAL LOOKUP
--
-- The private schema is not exposed to Flutter.
--
-- Edge Functions instead call this narrowly scoped RPC using
-- a server-side secret/service credential.
-- ============================================================

create or replace function public.auth_lookup_login_credential(
  p_login_name_normalized text,
  p_pin_fingerprint text
)
returns table (
  profile_id uuid,
  pin_hash text,
  role public.user_role,
  is_active boolean
)
language sql
security definer
set search_path = ''
as $$
  select
    c.profile_id,
    c.pin_hash,
    p.role,
    p.is_active
  from private.login_credentials c
  join public.profiles p
    on p.id = c.profile_id
  where c.login_name_normalized = p_login_name_normalized
    and c.pin_fingerprint = p_pin_fingerprint
  limit 1;
$$;


-- PostgreSQL grants EXECUTE on new functions to PUBLIC by
-- default, so explicitly lock this server-only function down.
revoke all
on function public.auth_lookup_login_credential(text, text)
from public;

revoke all
on function public.auth_lookup_login_credential(text, text)
from anon;

revoke all
on function public.auth_lookup_login_credential(text, text)
from authenticated;

grant execute
on function public.auth_lookup_login_credential(text, text)
to service_role;


-- ============================================================
-- SERVER-ONLY CREDENTIAL UPSERT
--
-- Used later when:
--   - creating a Forestring account
--   - changing a user's PIN
--   - migrating Firebase users
--
-- Raw PIN is NEVER passed into PostgreSQL.
-- The trusted Edge Function prepares the hash/fingerprint first.
-- ============================================================

create or replace function public.auth_upsert_login_credential(
  p_profile_id uuid,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = p_profile_id
  ) then
    raise exception
      'Profile % does not exist.',
      p_profile_id;
  end if;

  insert into private.login_credentials (
    profile_id,
    login_name_normalized,
    pin_hash,
    pin_fingerprint
  )
  values (
    p_profile_id,
    p_login_name_normalized,
    p_pin_hash,
    p_pin_fingerprint
  )
  on conflict (profile_id)
  do update set
    login_name_normalized = excluded.login_name_normalized,
    pin_hash = excluded.pin_hash,
    pin_fingerprint = excluded.pin_fingerprint;
end;
$$;


revoke all
on function public.auth_upsert_login_credential(
  uuid,
  text,
  text,
  text
)
from public;

revoke all
on function public.auth_upsert_login_credential(
  uuid,
  text,
  text,
  text
)
from anon;

revoke all
on function public.auth_upsert_login_credential(
  uuid,
  text,
  text,
  text
)
from authenticated;

grant execute
on function public.auth_upsert_login_credential(
  uuid,
  text,
  text,
  text
)
to service_role;


-- ============================================================
-- SERVER-ONLY RATE LIMIT READ
-- ============================================================

create or replace function public.auth_get_login_rate_limit(
  p_bucket_key text
)
returns table (
  failed_attempts integer,
  window_started_at timestamptz,
  locked_until timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    r.failed_attempts,
    r.window_started_at,
    r.locked_until
  from private.login_rate_limits r
  where r.bucket_key = p_bucket_key;
$$;


revoke all
on function public.auth_get_login_rate_limit(text)
from public;

revoke all
on function public.auth_get_login_rate_limit(text)
from anon;

revoke all
on function public.auth_get_login_rate_limit(text)
from authenticated;

grant execute
on function public.auth_get_login_rate_limit(text)
to service_role;


-- ============================================================
-- SERVER-ONLY RATE LIMIT WRITE
--
-- The Edge Function calculates the actual rate-limit policy.
-- This RPC only persists the resulting state.
-- ============================================================

create or replace function public.auth_set_login_rate_limit(
  p_bucket_key text,
  p_failed_attempts integer,
  p_window_started_at timestamptz,
  p_locked_until timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_failed_attempts < 0 then
    raise exception
      'failed_attempts cannot be negative.';
  end if;

  insert into private.login_rate_limits (
    bucket_key,
    failed_attempts,
    window_started_at,
    locked_until
  )
  values (
    p_bucket_key,
    p_failed_attempts,
    p_window_started_at,
    p_locked_until
  )
  on conflict (bucket_key)
  do update set
    failed_attempts = excluded.failed_attempts,
    window_started_at = excluded.window_started_at,
    locked_until = excluded.locked_until;
end;
$$;


revoke all
on function public.auth_set_login_rate_limit(
  text,
  integer,
  timestamptz,
  timestamptz
)
from public;

revoke all
on function public.auth_set_login_rate_limit(
  text,
  integer,
  timestamptz,
  timestamptz
)
from anon;

revoke all
on function public.auth_set_login_rate_limit(
  text,
  integer,
  timestamptz,
  timestamptz
)
from authenticated;

grant execute
on function public.auth_set_login_rate_limit(
  text,
  integer,
  timestamptz,
  timestamptz
)
to service_role;


-- ============================================================
-- SERVER-ONLY RATE LIMIT CLEAR
-- ============================================================

create or replace function public.auth_clear_login_rate_limit(
  p_bucket_key text
)
returns void
language sql
security definer
set search_path = ''
as $$
  delete
  from private.login_rate_limits
  where bucket_key = p_bucket_key;
$$;


revoke all
on function public.auth_clear_login_rate_limit(text)
from public;

revoke all
on function public.auth_clear_login_rate_limit(text)
from anon;

revoke all
on function public.auth_clear_login_rate_limit(text)
from authenticated;

grant execute
on function public.auth_clear_login_rate_limit(text)
to service_role;


-- ============================================================
-- EXPLICIT TABLE PERMISSION LOCKDOWN
-- ============================================================

revoke all
on table private.login_credentials
from public, anon, authenticated;

revoke all
on table private.login_rate_limits
from public, anon, authenticated;
