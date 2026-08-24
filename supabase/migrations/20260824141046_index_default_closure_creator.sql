create index default_closure_periods_created_by_idx
on public.default_closure_periods (created_by)
where created_by is not null;
