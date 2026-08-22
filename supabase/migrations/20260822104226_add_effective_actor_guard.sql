-- ============================================================
-- Forestring v3
-- Canonical effective-access guard for mutation RPC actors
--
-- All human-initiated SECURITY DEFINER mutation RPCs should
-- eventually call this helper exactly once for their actor.
--
-- Canonical source:
--   private.profile_has_effective_access(uuid)
-- ============================================================


create or replace function
private.require_effective_actor(
  p_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin

  if p_actor_id is null
     or not private.profile_has_effective_access(
       p_actor_id
     ) then

    raise insufficient_privilege
      using message =
        'FORESTRING_EFFECTIVE_ACCESS_REQUIRED';

  end if;

end;
$$;


-- Internal helper only.
-- It is called from trusted SECURITY DEFINER RPCs,
-- never directly from Flutter or Edge.
revoke all
on function
private.require_effective_actor(uuid)
from
  public,
  anon,
  authenticated,
  service_role;