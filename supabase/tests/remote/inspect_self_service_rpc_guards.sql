-- ============================================================
-- Forestring v3
-- Self-service RPC effective-access preflight
-- READ ONLY
-- ============================================================

with user_functions as (
  select
    p.oid,
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(
      p.oid
    ) as arguments,
    pg_get_functiondef(
      p.oid
    ) as definition

  from pg_proc p

  join pg_namespace n
    on n.oid = p.pronamespace

  where n.nspname in (
    'public',
    'private'
  )

    -- IMPORTANT:
    -- pg_get_functiondef() must not be called for aggregates.
    and p.prokind = 'f'
),

target_functions as (
  select
    f.function_name as name,
    f.arguments,
    f.definition,

    has_function_privilege(
      'authenticated',
      f.oid,
      'EXECUTE'
    ) as authenticated_execute,

    has_function_privilege(
      'service_role',
      f.oid,
      'EXECUTE'
    ) as service_role_execute

  from user_functions f

  where f.schema_name = 'public'

    and f.function_name in (
      'book_lesson_right',
      'cancel_lesson',
      'rebook_lesson'
    )
),

legacy_refs as (
  select
    f.schema_name,
    f.function_name as caller,
    f.arguments,

    (
      lower(f.definition)
      like '%rebook_lesson(%'
    ) as references_rebook_lesson,

    (
      lower(f.definition)
      like '%lesson_rebooking_credits%'
    ) as references_legacy_credits

  from user_functions f

  where
    lower(f.definition)
      like '%rebook_lesson(%'

    or

    lower(f.definition)
      like '%lesson_rebooking_credits%'
)

select jsonb_pretty(
  jsonb_build_object(

    'functions',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'name',
                f.name,

              'arguments',
                f.arguments,

              'authenticatedExecute',
                f.authenticated_execute,

              'serviceRoleExecute',
                f.service_role_execute,

              'definition',
                f.definition
            )
            order by
              f.name,
              f.arguments
          )

          from target_functions f
        ),
        '[]'::jsonb
      ),

    'legacyReferences',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'schema',
                r.schema_name,

              'caller',
                r.caller,

              'arguments',
                r.arguments,

              'referencesRebookLesson',
                r.references_rebook_lesson,

              'referencesLegacyCredits',
                r.references_legacy_credits
            )
            order by
              r.schema_name,
              r.caller,
              r.arguments
          )

          from legacy_refs r
        ),
        '[]'::jsonb
      )
  )
) as self_service_rpc_preflight;
