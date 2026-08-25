create or replace function public.admin_get_effective_actor_context(
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_role public.user_role;
  v_branch_id uuid;
begin

  if p_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTOR_REQUIRED';
  end if;


  perform private.require_effective_actor(
    p_actor_id
  );


  select
    p.role,
    p.branch_id
  into
    v_role,
    v_branch_id
  from public.profiles p
  where p.id = p_actor_id;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTOR_NOT_FOUND';
  end if;


  return jsonb_build_object(
    'role',
      v_role,

    'branchId',
      v_branch_id
  );

end;
$function$;


revoke all
on function public.admin_get_effective_actor_context(uuid)
from public, anon, authenticated;


grant execute
on function public.admin_get_effective_actor_context(uuid)
to service_role;
