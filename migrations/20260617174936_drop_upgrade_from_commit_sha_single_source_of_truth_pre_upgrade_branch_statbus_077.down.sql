-- Revert STATBUS-077: re-add public.upgrade.from_commit_sha + its CHECK (mirror of
-- 20260616104500's up). Restores the SOURCE CommitSHA column (the now-removed second
-- copy of the source commit). NULL for all existing rows — no backfill; recovery for
-- such rows falls back to the pinned pre-upgrade branch (the same path STATBUS-077
-- makes the sole mechanism). Reversibility only; the service code no longer reads or
-- writes this column.
BEGIN;

ALTER TABLE public.upgrade
  ADD COLUMN from_commit_sha text;

COMMENT ON COLUMN public.upgrade.from_commit_sha IS
  'The SOURCE commit (CommitSHA: 40-char lowercase hex) the upgrade started from — the authoritative rollback/recovery restore target. Always resolves as a git ref, unlike the display-only from_commit_version (a CommitVersion). Captured as `git rev-parse HEAD` at the scheduled->in_progress claim (STATBUS-062). NULL for rows written before STATBUS-062 or when capture failed; recovery then falls back to the pinned pre-upgrade branch.';

-- Invariant: a stored from_commit_sha is a full 40-char hex CommitSHA (mirrors
-- chk_upgrade_commit_sha_is_full_hex on the target commit_sha). NULL is allowed
-- (legacy / capture-failed rows recover via the pre-upgrade branch).
ALTER TABLE public.upgrade
  ADD CONSTRAINT chk_upgrade_from_commit_sha_is_full_hex
  CHECK (from_commit_sha IS NULL OR from_commit_sha ~ '^[a-f0-9]{40}$');

END;
