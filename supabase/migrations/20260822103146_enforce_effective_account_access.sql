-- ============================================================
-- Forestring v3
-- Effective account access
--
-- profiles.is_active:
--   administrative account state
--
-- effective access:
--   whether this identity may use the app RIGHT NOW
--
-- Staff:
--   withdrawal_date is first non-working / inaccessible day.
--
-- Student:
--   withdrawal_date is first non-enrolled / inaccessible day.
--
-- This helper is used by:
--   1. PIN login credential lookup
--   2. RLS for already-authenticated sessions
--
-- SECURITY DEFINER mutation RPCs are patched separately after
-- this foundation passes regression.
-- ============================================================


-- ============================================================
-- 1. CAN THIS PROFILE USE THE APP TODAY?
-- ============================================================

create or replace function
private.profile_has_effective_access(
  p_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1

    from public.profiles p

    left join public.teachers t
      on t.id = p.id

    left join public.students s
      on s.id = p.id

    where p.id =
          p_profile_id

      and p.is_active = true

      and (
        -- MASTER
        p.role =
          'master'::public.user_role


        -- STAFF
        or (
          p.role in (
            'teacher'::public.user_role,
            'manager'::public.user_role
          )

          -- A staff profile must have the canonical teachers row.
          and t.id is not null

          and (
            t.withdrawal_date is null

            or (
              pg_catalog.now()
              at time zone 'Asia/Seoul'
            )::date <
               t.withdrawal_date
          )
        )


        -- STUDENT
        or (
          p.role =
            'student'::public.user_role

          and s.id is not null

          and s.status =
            'active'::public.student_status

          and (
            s.withdrawal_date is null

            or (
              pg_catalog.now()
              at time zone 'Asia/Seoul'
            )::date <
               s.withdrawal_date
          )
        )
      )
  );
$$;


revoke all
on function
private.profile_has_effective_access(uuid)
from public, anon, authenticated;



-- ============================================================
-- 2. RLS CURRENT-USER GATE
--
-- Every existing RLS policy already calls is_active_user().
-- Replacing this helper therefore closes old authenticated
-- sessions without rewriting every SELECT policy.
-- ============================================================

create or replace function
private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.profile_has_effective_access(
      (select auth.uid())
    );
$$;


revoke all
on function
private.is_active_user()
from public, anon;


grant execute
on function
private.is_active_user()
to authenticated;



-- ============================================================
-- 3. MASTER HELPER
--
-- Keep master checks consistent with the same effective-access
-- source instead of maintaining an independent "active" rule.
-- ============================================================

create or replace function
private.is_master()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.profile_has_effective_access(
      (select auth.uid())
    )

    and exists (
      select 1

      from public.profiles p

      where p.id =
            (select auth.uid())

        and p.role =
            'master'::public.user_role
    );
$$;


revoke all
on function
private.is_master()
from public, anon;


grant execute
on function
private.is_master()
to authenticated;



-- ============================================================
-- 4. LOGIN LOOKUP
--
-- Keep the Edge contract unchanged:
--
--   Credential.is_active
--
-- but return EFFECTIVE access rather than only the raw
-- profiles.is_active flag.
--
-- Therefore login-with-pin itself does not need another
-- staff-specific branch.
-- ============================================================

create or replace function
public.auth_lookup_login_credential(
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

    private.profile_has_effective_access(
      c.profile_id
    ) as is_active

  from private.login_credentials c

  join public.profiles p
    on p.id =
       c.profile_id

  where c.login_name_normalized =
        p_login_name_normalized

    and c.pin_fingerprint =
        p_pin_fingerprint

  limit 1;
$$;


revoke all
on function
public.auth_lookup_login_credential(
  text,
  text
)
from public, anon, authenticated;


grant execute
on function
public.auth_lookup_login_credential(
  text,
  text
)
to service_role;