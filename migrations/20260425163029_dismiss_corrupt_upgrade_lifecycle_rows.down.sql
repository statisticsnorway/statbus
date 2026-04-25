-- Down migration: no-op.
--
-- The up migration moves corrupt pre-terminal rows (state in
-- 'available'/'scheduled'/'in_progress' with timestamp columns
-- inconsistent with chk_upgrade_state_attributes) to state='dismissed'
-- with dismissed_at=NOW() and a backfill marker in `error`. Reversing
-- those would re-introduce the constraint-violating shape and immediately
-- crash the next markCIImagesFailed cycle.
--
-- This is a one-way data fix; only the structural code fix in
-- cli/internal/upgrade/service.go:markCIImagesFailed has a reversible
-- counterpart (revert the commit). Same pattern as
-- 20260421113653_upgrade_completed_requires_log_pointer.down.sql, which
-- backfills log_relative_file_path with the sentinel
-- 'unknown-pre-2026-04-15' and likewise does not reverse the data write.

SELECT 1;
