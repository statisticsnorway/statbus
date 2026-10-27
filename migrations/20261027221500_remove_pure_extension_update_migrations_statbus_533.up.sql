-- Migration 20261027221500: remove pure extension-update migration ledger rows
--
-- STATBUS-533 (owner-approved design): extension upgrades are the migrate
-- runner's own lifecycle step (cli/internal/migrate/extensions.go), executed
-- on the target database BEFORE the pending-migration set is computed. The
-- pure extension-update migration FILES are deleted with this change:
--
--   20261015163419  sql_saga 1.0 -> 1.1
--   20261018113522  jsonb_stats 2.0.0 -> 3.0.0
--   20261021130641  sql_saga 1.1/1.2 -> 1.3
--   20261027135139  sql_saga 1.0-1.3 -> 1.4
--
-- Their db.migration rows must go with them: db.migration records ordinary
-- schema migrations only, and assert-db-at-head compares the row set against
-- the on-disk files, so a leftover row for a deleted file would read as
-- drift forever. There is no compatibility registry and no fake history for
-- these IDs; the upgrade events themselves are audited, per database, in
-- db.extension_upgrade (written by the runner at the moment of the upgrade).
--
-- The DELETE is deterministic on full replay (no rows match) and on
-- incremental upgrade (rows present from when the files existed), and does
-- not depend on any other current state.
BEGIN;

DELETE FROM db.migration
 WHERE version IN (20261015163419, 20261018113522, 20261021130641, 20261027135139);

END;
