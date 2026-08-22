with funcs as (
  select
    p.oid,
    p.proname as function_name,

    pg_get_function_identity_arguments(
      p.oid
    ) as arguments,

    pg_get_function_result(
      p.oid
    ) as result_type,

    pg_get_functiondef(
      p.oid
    ) as definition

  from pg_proc p

  join pg_namespace n
    on n.oid = p.pronamespace

  where n.nspname = 'public'
    and p.prokind = 'f'
    and p.prosecdef = true

    and has_function_privilege(
      'authenticated',
      p.oid,
      'EXECUTE'
    )
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
      like '%require_effective_actor%'
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
  function_name,
  arguments,
  result_type,
  appears_to_write,
  uses_auth_uid,
  uses_actor_parameter,
  uses_raw_is_active,
  uses_effective_access,

  case

    when uses_effective_access
      then 'EFFECTIVE_ACCESS_OK'

    when uses_auth_uid
         and uses_raw_is_active
      then 'PATCH_CANDIDATE'

    when uses_auth_uid
      then 'REVIEW_AUTH'

    when uses_actor_parameter
      then 'REVIEW_ACTOR_PARAMETER'

    else 'REVIEW_NO_ACTOR'

  end as audit_status

from classified

order by
  case
    when uses_effective_access then 4
    when uses_auth_uid and uses_raw_is_active then 0
    when uses_auth_uid then 1
    when uses_actor_parameter then 2
    else 3
  end,

  function_name,
  arguments;
