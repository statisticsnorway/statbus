-- Down migration: no-op.
--
-- The up migration reconstructs import_source_column/import_mapping rows
-- that a construction-order-dependent bug in import.cleanup_orphaned_synced_mappings
-- (migration 20260422011930) can wrongly delete during a full-from-migrations
-- seed replay (STATBUS-312). Reversing it would delete the reconstructed
-- rows again, restoring exactly the corrupt state this migration exists to
-- fix — never correct, even as a "clean" rollback.
--
-- This is a one-way data fix; the only reversible counterpart is the
-- structural code fix (if any lands for the ordering bug itself) via
-- reverting that commit. Same pattern as
-- 20260425163029_dismiss_corrupt_upgrade_lifecycle_rows.down.sql and
-- 20260828225222_repair_tag_object_sha_pollution_rc14_rc15.down.sql.

SELECT 1;
