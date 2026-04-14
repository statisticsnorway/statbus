-- Migration 20260414193000: fix_upgrade_notify_payload
--
-- The trigger previously sent NEW.commit_sha (raw 40-char hex) as the
-- pg_notify payload for the 'upgrade_apply' channel. The upgrade service's
-- ValidateVersion regex requires the 'sha-' prefix
-- (^(v\d{4}\.\d{2}\.\d+(-[\w.]+)?|sha-[a-f0-9]{7,40})$), so the raw hex
-- was silently rejected and scheduleImmediate was never called. User-initiated
-- upgrades therefore fell back to the poll ticker (~6h default, or whatever
-- UPGRADE_CHECK_INTERVAL is set to on the server) instead of being picked up
-- within milliseconds. Fix: send 'sha-' || left(commit_sha, 12).
BEGIN;

CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
DECLARE
  v_payload text;
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    v_payload := 'sha-' || left(NEW.commit_sha, 12);
    RAISE NOTICE 'upgrade_notify_daemon: sha=% payload=%', NEW.commit_sha, v_payload;
    PERFORM pg_notify('upgrade_apply', v_payload);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

END;
