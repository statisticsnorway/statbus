BEGIN;

-- Restore without SET search_path (original versions)
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

CREATE OR REPLACE FUNCTION public.upgrade_notify_frontend()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $upgrade_notify_frontend$
BEGIN
  PERFORM pg_notify('worker_status', '{"type":"upgrade_changed"}');
  RETURN COALESCE(NEW, OLD);
END;
$upgrade_notify_frontend$;

END;
