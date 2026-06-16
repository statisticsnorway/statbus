-- STATBUS-062: ground the rollback/recovery restore target on the SOURCE
-- CommitSHA (authoritative, always resolves as a git ref) instead of the
-- display-only from_commit_version (a CommitVersion = `git describe` output,
-- never-for-lookup). Mirrors the TARGET identity pair commit_sha (authoritative)
-- + commit_version (display) with a SOURCE pair from_commit_sha + from_commit_version.
--
-- executeUpgrade now records from_commit_sha = `git rev-parse HEAD` at the
-- scheduled->in_progress claim (the working tree is at the source there — the
-- target checkout is deferred to the recovery boot, STATBUS-060). recoveryRollback,
-- resumePostSwap, and the in-process rollback resolve the restore target from
-- this column; the pinned `pre-upgrade` branch becomes pure defense-in-depth.
--
-- Existing rows keep from_commit_sha = NULL (historical source commits are
-- unknown; a legacy in-flight row recovers via the pre-upgrade branch the old
-- binary pinned). No backfill.
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
