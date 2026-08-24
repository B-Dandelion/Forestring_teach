-- Trigger-only helper. It must not be callable through the Data API.
revoke all on function public.seed_default_closures_for_new_branch()
from public, anon, authenticated;
