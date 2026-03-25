-- Migration 20260325230737: grant_access_to_upgrade_and_system_info_tables
BEGIN;

-- The upgrade tracking migration (20260311174120) created RLS policies
-- but omitted table-level GRANTs. PostgreSQL requires BOTH:
--   1. GRANTs (table-level) — allow a role to attempt a query
--   2. RLS policies (row-level) — filter which rows are visible
-- Without GRANTs, PostgREST gets HTTP 403 before RLS even applies.

-- public.upgrade — upgrade lifecycle tracking
GRANT SELECT ON public.upgrade TO authenticated;
GRANT SELECT ON public.upgrade TO regular_user;
GRANT ALL ON public.upgrade TO admin_user;

-- public.system_info — system configuration (upgrade channel, etc.)
GRANT SELECT ON public.system_info TO authenticated;
GRANT SELECT ON public.system_info TO regular_user;
GRANT ALL ON public.system_info TO admin_user;

END;
