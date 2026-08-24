begin;

do $$
declare
  v_master_id uuid;
  v_manager_id uuid;
  v_manager_branch_id uuid;
  v_other_branch_id uuid;

  v_same_branch_allowed boolean := false;
  v_cross_branch_denied boolean := false;
  v_master_allowed boolean := false;
begin

  select p.id
  into v_master_id
  from public.profiles p
  where p.role = 'master'::public.user_role
    and p.is_active = true
  order by p.created_at
  limit 1;


  select
    p.id,
    p.branch_id
  into
    v_manager_id,
    v_manager_branch_id
  from public.profiles p
  where p.role = 'manager'::public.user_role
    and p.is_active = true
    and p.branch_id is not null
  order by p.created_at
  limit 1;


  select b.id
  into v_other_branch_id
  from public.branches b
  where b.is_active = true
    and b.id <> v_manager_branch_id
  order by b.created_at
  limit 1;


  if v_master_id is null
     or v_manager_id is null
     or v_other_branch_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: master, manager, and second branch';
  end if;


  begin
    perform public.admin_create_teacher_account_data(
      v_manager_id,
      null,
      '__MANAGER_CREATE_SCOPE_TEST__',
      '__MANAGER_CREATE_SCOPE_TEST__',
      'unused',
      'unused',
      v_manager_branch_id,
      '[]'::jsonb
    );
  exception
    when others then
      if sqlerrm = 'FORESTRING_PROFILE_ID_REQUIRED' then
        v_same_branch_allowed := true;
      else
        raise;
      end if;
  end;


  begin
    perform public.admin_create_teacher_account_data(
      v_manager_id,
      null,
      '__MANAGER_CREATE_SCOPE_TEST__',
      '__MANAGER_CREATE_SCOPE_TEST__',
      'unused',
      'unused',
      v_other_branch_id,
      '[]'::jsonb
    );
  exception
    when others then
      if sqlerrm = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then
        v_cross_branch_denied := true;
      else
        raise;
      end if;
  end;


  begin
    perform public.admin_create_teacher_account_data(
      v_master_id,
      null,
      '__MASTER_CREATE_SCOPE_TEST__',
      '__MASTER_CREATE_SCOPE_TEST__',
      'unused',
      'unused',
      v_other_branch_id,
      '[]'::jsonb
    );
  exception
    when others then
      if sqlerrm = 'FORESTRING_PROFILE_ID_REQUIRED' then
        v_master_allowed := true;
      else
        raise;
      end if;
  end;


  if not v_same_branch_allowed then
    raise exception
      'TEST_FAILED: manager was not allowed through same-branch scope';
  end if;

  if not v_cross_branch_denied then
    raise exception
      'TEST_FAILED: manager cross-branch creation was not denied';
  end if;

  if not v_master_allowed then
    raise exception
      'TEST_FAILED: master was not allowed through cross-branch scope';
  end if;
end;
$$;

rollback;
