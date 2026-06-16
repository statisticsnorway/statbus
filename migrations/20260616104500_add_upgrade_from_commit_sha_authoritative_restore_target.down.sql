-- Revert STATBUS-062: drop the SOURCE CommitSHA column + its CHECK.
-- recoveryRollback/resumePostSwap/in-process rollback then resolve the restore
-- target from the pinned pre-upgrade branch only (from_commit_version stays
-- display-only).
BEGIN;

ALTER TABLE public.upgrade
  DROP CONSTRAINT IF EXISTS chk_upgrade_from_commit_sha_is_full_hex;

ALTER TABLE public.upgrade
  DROP COLUMN IF EXISTS from_commit_sha;

END;
