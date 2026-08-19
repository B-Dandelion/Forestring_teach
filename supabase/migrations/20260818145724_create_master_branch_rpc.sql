-- ============================================================
-- Forestring v3
-- Master branch creation RPC
-- ============================================================

create or replace function public.create_branch(
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_branch_id uuid;
begin

  -- master only
  if not exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'master'::public.user_role
      and p.is_active = true
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  -- trim + collapse spaces
  v_name :=
    regexp_replace(
      btrim(coalesce(p_name, '')),
      '[[:space:]]+',
      ' ',
      'g'
    );

  if v_name = ''
     or length(v_name) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_BRANCH_NAME';
  end if;

  insert into public.branches (
    name,
    is_active
  )
  values (
    v_name,
    true
  )
  returning id
  into v_branch_id;

  return v_branch_id;

exception
  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NAME_ALREADY_EXISTS';
end;
$$;


revoke all
on function public.create_branch(text)
from public, anon;


grant execute
on function public.create_branch(text)
to authenticated;
