-- Migration 20260416120000: drop_progress_log_from_upgrade
--
-- Final wave of the file-first upgrade-log migration (#17). The service
-- now writes the full narrative to tmp/upgrade-logs/<basename>.log, paired
-- with a .bundle.txt support bundle at terminal transitions. The admin UI
-- fetches log tails via Caddy's /upgrade-logs/<name> handle, keyed by the
-- log_relative_file_path column added in 20260415220000.
--
-- progress_log is no longer read or written by any consumer (Go service,
-- REST API clients, admin UI) and can be dropped.
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN progress_log;

END;
