-- Down Migration 20260326004538: notify_frontend_on_upgrade_changes
BEGIN;

DROP TRIGGER IF EXISTS upgrade_notify_frontend_trigger ON public.upgrade;
DROP FUNCTION IF EXISTS public.upgrade_notify_frontend();

END;
