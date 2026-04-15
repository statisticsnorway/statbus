-- Down migration: restore truncated-SHA trigger, drop CHECK constraint.
-- Note: the orphan short-SHA rows deleted by the up migration are NOT
-- recreated — they were duplicates of existing full-SHA rows and are
-- irreversible by design.
BEGIN;

ALTER TABLE public.upgrade DROP CONSTRAINT IF EXISTS chk_upgrade_commit_sha_is_full_hex;

CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
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
