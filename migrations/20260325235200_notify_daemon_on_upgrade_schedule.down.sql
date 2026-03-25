-- Down Migration 20260325235200: notify_daemon_on_upgrade_schedule
BEGIN;

DROP TRIGGER IF EXISTS upgrade_notify_daemon_trigger ON public.upgrade;
DROP FUNCTION IF EXISTS public.upgrade_notify_daemon();

END;
