-- Migration 20260415220000: add_log_relative_file_path_to_upgrade (#17)
--
-- Wave 5, commit (a1): move upgrade progress logs out of the DB column into
-- per-upgrade files under tmp/upgrade-logs/. This column stores the basename
-- of the log file (e.g. "42-v2026.03.1-rc.6-20260415T142305Z.log"); the Go
-- service joins it with {projDir}/tmp/upgrade-logs/ at read time.
--
-- progress_log is left in place during Wave 5 so each intermediate commit
-- keeps master building. It is dropped in the final Wave 5 commit after the
-- admin UI stops reading it.
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN log_relative_file_path text;

COMMENT ON COLUMN public.upgrade.log_relative_file_path IS
    'Basename of the per-upgrade log file under tmp/upgrade-logs/. Populated by the upgrade service at start. Superseded progress_log (to be dropped once the UI migrates to fetching /upgrade-logs/<name>).';

COMMENT ON COLUMN public.upgrade.progress_log IS
    'DEPRECATED 2026-04-15 (#17): superseded by log_relative_file_path + tmp/upgrade-logs/. New rows no longer populate this column; it will be dropped in a later Wave 5 commit after the admin UI switches to file-backed log fetches.';

END;
