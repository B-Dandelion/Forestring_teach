-- ============================================================
-- Forestring v3
-- Teacher creation with branch
-- ============================================================

create or replace function public.admin_create_teacher_account_data(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_work_hours jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;

  -- Reuse the already-tested account creation transaction.
  perform public.admin_create_teacher_account_data(
    p_actor_id,
    p_profile_id,
    p_display_name,
    p_login_name_normalized,
    p_pin_hash,
    p_pin_fingerprint,
    p_work_hours
  );

  update public.profiles
  set branch_id = p_branch_id
  where id = p_profile_id;

  return p_profile_id;
end;
$$;


-- Old branch-less function must no longer be callable
-- directly by the Edge Function service role.
revoke execute
on function public.admin_create_teacher_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
)
from service_role;


revoke all
on function public.admin_create_teacher_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  jsonb
)
from public, anon, authenticated;


grant execute
on function public.admin_create_teacher_account_data(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  jsonb
)
to service_role;
