-- Add a content_hash column to db.migration so the migrate runner can
-- detect in-place edits to already-applied migration files (the rc63
-- "fix-by-editing" pattern that violated migration immutability and
-- left releases internally inconsistent).
--
-- Lifecycle (per plan section R, commit 2/4):
-- - Column starts NULLABLE. Legacy rows get NULL; lazy-backfilled by
--   the runner on the next `./sb migrate up` after this migration.
-- - The runner stamps the hash of every migration's file bytes after
--   apply (or via lazy backfill for legacy rows).
-- - On every `./sb migrate up`, before the pending-only filter, the
--   runner compares the live file's sha256 to the stored hash for
--   each non-NULL row. Mismatch fires an error with two arms:
--     * Migration version is in a released tag → immutability
--       violation (hard fail; create a new migration instead).
--     * Migration version is unreleased WIP → "Run: ./sb migrate
--       redo <version>" (recoverable).
-- - The runner also lazy-backfills any NULL content_hash rows in the
--   same sweep (UPDATE with computed hash; no warning).
--
-- The companion `./sb migrate redo` primitive (introduced alongside
-- this column) re-runs down + up for a WIP-edited migration, deletes
-- the tracking row, and re-inserts so the content_hash refreshes.

BEGIN;

ALTER TABLE db.migration ADD COLUMN content_hash text;

COMMENT ON COLUMN db.migration.content_hash IS
    'sha256 of the migration file bytes at apply time. NULL on legacy '
    'rows pending lazy backfill on next migrate up. The runner enforces '
    'mismatch-detection: a stored hash that no longer matches the live '
    'file is either an immutability violation (released migration edited) '
    'or a WIP edit recoverable via `./sb migrate redo <version>`. '
    'Per plan-rc.66 section R.';

COMMIT;
