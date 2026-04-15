-- Reverse migration 20260415220000: add_log_relative_file_path_to_upgrade (#17)
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN IF EXISTS log_relative_file_path;

COMMENT ON COLUMN public.upgrade.progress_log IS
    'Tail of the upgrade progress log (last ~50 lines). Populated on success, rollback, or direct failure by the upgrade service so operators can inspect what happened from the admin UI.';

END;
