-- Root cause: upgrade_notify_daemon truncated commit_sha to 12 chars in the
-- pg_notify payload. scheduleImmediate re-inserted the short SHA as a new
-- row (UNIQUE is exact-text, not prefix-aware). Fix: send full SHA, delete
-- orphan duplicates, pin format with CHECK.
BEGIN;

-- 1. Trigger: full-SHA payload.
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
DECLARE
  v_payload text;
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    v_payload := 'sha-' || NEW.commit_sha;
    RAISE NOTICE 'upgrade_notify_daemon: sha=% payload=%', NEW.commit_sha, v_payload;
    PERFORM pg_notify('upgrade_apply', v_payload);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

-- 2. Delete orphan short-SHA rows whose full-SHA twin already exists.
--    Self-join on prefix: the short is a prefix of the full; short has
--    length < 40, full has length = 40. commit_sha is hex so LIKE has no
--    metacharacter collisions in the prefix itself.
DELETE FROM public.upgrade AS short_row
 WHERE length(short_row.commit_sha) < 40
   AND EXISTS (
     SELECT 1
       FROM public.upgrade AS full_row
      WHERE length(full_row.commit_sha) = 40
        AND full_row.commit_sha LIKE short_row.commit_sha || '%'
   );

-- 3. Verify nothing short remains. Fires loudly if any tenant has a
--    stranded short-SHA row that paralegal's sweep did not observe
--    (no matching full-SHA twin → not deleted by step 2). Operator
--    must then resolve manually before re-running. Fail-closed.
DO $verify$
DECLARE
  v_count int;
  v_sample text;
BEGIN
  SELECT count(*), string_agg(commit_sha, ', ' ORDER BY commit_sha)
    INTO v_count, v_sample
    FROM public.upgrade
   WHERE commit_sha !~ '^[a-f0-9]{40}$';
  IF v_count > 0 THEN
    RAISE EXCEPTION
      'fix_upgrade_sha_truncation: % row(s) with non-full-hex commit_sha remain: %. '
      'Resolve manually (git rev-parse + UPDATE, or DELETE if orphaned) then re-run.',
      v_count, v_sample;
  END IF;
END;
$verify$;

-- 4. Invariant: any future short/malformed insert fails at the DB layer.
ALTER TABLE public.upgrade
  ADD CONSTRAINT chk_upgrade_commit_sha_is_full_hex
  CHECK (commit_sha ~ '^[a-f0-9]{40}$');

END;
