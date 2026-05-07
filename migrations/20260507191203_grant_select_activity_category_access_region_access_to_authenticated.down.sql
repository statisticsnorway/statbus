-- Down migration: revoke the SELECT grants added in the up migration.
-- Restores the (buggy) state where regular_user cannot UPDATE public.activity
-- or public.location.

REVOKE SELECT ON public.activity_category_access FROM authenticated;
REVOKE SELECT ON public.region_access FROM authenticated;
