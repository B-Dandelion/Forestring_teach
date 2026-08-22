-- ============================================================
-- Forestring v3
-- Effective-access audit for SECURITY DEFINER RPCs
-- READ ONLY
--
-- Goal:
-- Find user-initiated write RPCs that may still authorize using
-- only profiles.is_active instead of the canonical
-- private.profile_has_effective_access().
-- ============================================================

with funcs as (
  select
    p.oid,

    n.nspname
      as schema_name,

    p.proname
      as function_name,

    pg_get_function_identity_arguments(
      p.oid
    ) as arguments,

    pg_get_function_result(
      p.oid
    ) as result_type,

    pg_get_functiondef(
      p.oid
    ) as definition,

    p.prosecdef
      as security_definer,

    has_function_privilege(
      'authenticated',
      p.oid,
      'EXECUTE'
    ) as authenticated_execute,

    has_function_privilege(
      'service_role',
      p.oid,
      'EXECUTE'
    ) as service_role_execute

  from pg_proc p

  join pg_namespace n
    on n.oid = p.pronamespace

  where n.nspname in (
    'public',
    'private'
  )

    and p.prokind = 'f'
),

classified as (
  select
    *,

    (
      lower(definition)
      like '%auth.uid%'
    ) as uses_auth_uid,

    (
      lower(definition)
      like '%p_actor_id%'
    ) as uses_actor_parameter,

    (
      lower(definition)
      like '%is_active = true%'
      or
      lower(definition)
      like '%is_active=true%'
    ) as uses_raw_is_active,

    (
      lower(definition)
      like '%profile_has_effective_access%'
      or
      lower(definition)
      like '%private.is_active_user%'
    ) as uses_effective_access,

    (
      lower(definition)
      like '%insert into%'
      or
      lower(definition)
      like '%update public.%'
      or
      lower(definition)
      like '%delete from%'
    ) as appears_to_write

  from funcs
)

select
  schema_name,
  function_name,
  arguments,
  authenticated_execute,
  service_role_execute,
  uses_auth_uid,
  uses_actor_parameter,
  uses_raw_is_active,
  uses_effective_access,

  case
    when
      appears_to_write
      and security_definer
      and (
        uses_auth_uid
        or uses_actor_parameter
      )
      and uses_raw_is_active
      and not uses_effective_access
    then 'PATCH_CANDIDATE'

    when
      appears_to_write
      and security_definer
      and (
        uses_auth_uid
        or uses_actor_parameter
      )
      and uses_effective_access
    then 'EFFECTIVE_ACCESS_OK'

    when
      appears_to_write
      and security_definer
      and (
        uses_auth_uid
        or uses_actor_parameter
      )
    then 'REVIEW'

    else 'OTHER'
  end as audit_status

from classified

where
  security_definer = true

  and appears_to_write = true

  and (
    uses_auth_uid
    or uses_actor_parameter
  )

order by
  case
    when
      uses_raw_is_active
      and not uses_effective_access
    then 0
    when
      not uses_effective_access
    then 1
    else 2
  end,

  schema_name,
  function_name,
  arguments;
