-- STATBUS-077: REMOVE public.upgrade.from_commit_sha (added by 20260616104500,
-- STATBUS-062). King's ruling — ONE source of truth for recovery: the pinned
-- `pre-upgrade` BRANCH (git branch -f pre-upgrade HEAD, set before any destructive
-- step). The source commit was stored twice (branch + this column); the column was
-- redundant. recoveryRollback / resumePostSwap / the in-process rollback now resolve
-- the restore target solely from the branch (restoreTargetSHA="" -> restoreGitState's
-- pre-upgrade fallback, unconditional); the claim no longer writes the column.
-- from_commit_version (the display record, 20260424160235) is unaffected and stays.
--
-- Forward DROP (not a delete of 20260616104500): a new recorded migration drops the
-- column via `migrate up` on the local dev DB + every box — no recreate-database, no
-- recorded-row/missing-file mismatch (STATBUS-072 forward-migration discipline). The
-- named CHECK constraint depends solely on this column, so DROP COLUMN would cascade
-- it; we DROP CONSTRAINT IF EXISTS first to be explicit and order-independent.
BEGIN;

ALTER TABLE public.upgrade
  DROP CONSTRAINT IF EXISTS chk_upgrade_from_commit_sha_is_full_hex;

ALTER TABLE public.upgrade
  DROP COLUMN IF EXISTS from_commit_sha;

END;
