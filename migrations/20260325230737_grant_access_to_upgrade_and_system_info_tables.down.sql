-- Down Migration 20260325230737: grant_access_to_upgrade_and_system_info_tables
BEGIN;

REVOKE ALL ON public.upgrade FROM authenticated, regular_user, admin_user;
REVOKE ALL ON public.system_info FROM authenticated, regular_user, admin_user;

END;
