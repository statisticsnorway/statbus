-- Migration 20260325235200: notify_daemon_on_upgrade_schedule
BEGIN;

-- When scheduled_at is set on an upgrade row, automatically NOTIFY the daemon.
-- This allows the admin UI to trigger upgrades by PATCHing the row via PostgREST,
-- without needing a separate NOTIFY endpoint.
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $upgrade_notify_daemon$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    PERFORM pg_notify('upgrade_apply', NEW.version);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

CREATE TRIGGER upgrade_notify_daemon_trigger
  AFTER UPDATE ON public.upgrade
  FOR EACH ROW
  EXECUTE FUNCTION public.upgrade_notify_daemon();

END;
