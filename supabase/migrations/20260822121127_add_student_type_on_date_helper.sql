create or replace function private.student_type_on_date(
  p_student_id uuid,
  p_on date
)
returns public.student_type
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_type public.student_type;
  v_plan_type public.student_type;
  v_candidate_count integer;
begin
  if p_student_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_REQUIRED';
  end if;

  if p_on is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_DATE_REQUIRED';
  end if;

  select s.student_type
  into v_current_type
  from public.students s
  where s.id = p_student_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  select count(*)::integer
  into v_candidate_count
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(
    sp.branch_id,
    sp.semester_id
  ) bounds
  where sp.student_id = p_student_id
    and p_on between bounds.starts_on and bounds.ends_on;

  if v_candidate_count > 1 then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AMBIGUOUS_STUDENT_SEMESTER_PLAN_ON_DATE',
      detail =
        'student_id=' || p_student_id::text ||
        ', on=' || p_on::text ||
        ', candidate_count=' || v_candidate_count::text;
  end if;

  if v_candidate_count = 0 then
    return v_current_type;
  end if;

  select sp.student_type_snapshot
  into strict v_plan_type
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(
    sp.branch_id,
    sp.semester_id
  ) bounds
  where sp.student_id = p_student_id
    and p_on between bounds.starts_on and bounds.ends_on;

  return v_plan_type;
end;
$function$;

revoke all
on function private.student_type_on_date(uuid, date)
from public, anon, authenticated;