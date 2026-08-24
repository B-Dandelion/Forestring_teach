-- Student cancellation policy:
-- - Regular: 2 cancellations per logical 4-lesson slot / semester.
-- - Flex: 2 cancellations per complete group of 4 base rights.
-- - Every student cancellation counts again after rebooking the same right.
-- - Academy cancellations and carryover cancellations do not consume quota.

drop index if exists public.lesson_cancellation_events_one_count_per_right;

do $migration$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.cancel_lesson(uuid,text)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'public.cancel_lesson(uuid,text) was not found';
  end if;

  v_updated := replace(
    v_definition,
$old$
    -- --------------------------------------------------------
    -- If this entitlement has ALREADY consumed one quota,
    -- a later re-cancel does not consume another.
    -- --------------------------------------------------------

    if exists (
      select 1

      from public.lesson_cancellation_events e

      where e.lesson_right_id =
            v_right.id

        and e.counts_toward_limit = true
    ) then

      v_counts_toward_limit :=
        false;


    -- --------------------------------------------------------
    -- CARRYOVER
$old$,
$new$
    -- --------------------------------------------------------
    -- CARRYOVER
$new$
  );

  if v_updated = v_definition then
    raise exception 'Expected repeat-cancellation branch was not found';
  end if;

  v_definition := v_updated;

  v_updated := replace(
    v_definition,
$old$
    elsif v_right.origin =
          'carryover'::public.lesson_right_origin then
$old$,
$new$
    if v_right.origin =
       'carryover'::public.lesson_right_origin then
$new$
  );

  if v_updated = v_definition then
    raise exception 'Expected carryover branch opening was not found';
  end if;

  v_definition := v_updated;

  v_updated := replace(
    v_definition,
    '-- Limit = floor(base right count / 4)',
    '-- Limit = floor(base right count / 4) * 2'
  );

  if v_updated = v_definition then
    raise exception 'Expected flex cancellation limit comment was not found';
  end if;

  v_definition := v_updated;

  v_updated := replace(
    v_definition,
$old$
      v_cancellation_limit :=
        floor(
          v_flex_base_count::numeric / 4
        )::integer;
$old$,
$new$
      v_cancellation_limit :=
        floor(
          v_flex_base_count::numeric / 4
        )::integer * 2;
$new$
  );

  if v_updated = v_definition then
    raise exception 'Expected flex cancellation limit expression was not found';
  end if;

  execute v_updated;
end;
$migration$;

revoke all
on function public.cancel_lesson(uuid, text)
from public, anon;

grant execute
on function public.cancel_lesson(uuid, text)
to authenticated;

comment on function public.cancel_lesson(uuid, text) is
  'Cancels a canonical right-backed scheduled lesson and restores the same entitlement. Student cancellation quotas are regular=2 per logical slot/semester and flex=2*floor(base rights/4) per semester; every student re-cancellation of a regular/flex right consumes quota, while academy and carryover cancellations do not.';
