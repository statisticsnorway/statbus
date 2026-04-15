-- Down migration 20260416120000: drop_progress_log_from_upgrade
--
-- Re-adds progress_log as nullable TEXT so a schema rollback does not
-- break downstream objects that might still reference the column name.
-- Historical log tails are NOT restored — they lived only in the dropped
-- column. The post-drop service writes exclusively to tmp/upgrade-logs/
-- via log_relative_file_path, so rollback correctness does not depend on
-- this column being repopulated.
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN progress_log text;

COMMENT ON COLUMN public.upgrade.progress_log IS
    'DEPRECATED. Superseded by log_relative_file_path + tmp/upgrade-logs/. Re-added here only so a rollback of the drop migration does not break the schema; never populated by the live service.';

END;
