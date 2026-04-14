-- Down Migration 20260414193000: fix_upgrade_notify_payload
--
-- Restore the trigger to send raw commit_sha (pre-fix behaviour).
BEGIN;

CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    PERFORM pg_notify('upgrade_apply', NEW.commit_sha);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

END;
