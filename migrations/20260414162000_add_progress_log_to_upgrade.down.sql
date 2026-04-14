-- Down migration 20260414162000: add_progress_log_to_upgrade
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN progress_log;

END;
