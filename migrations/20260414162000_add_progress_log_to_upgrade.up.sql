-- Migration 20260414162000: add_progress_log_to_upgrade
--
-- Persist the tail of the upgrade progress log on public.upgrade so the
-- admin UI can show operators what happened during an upgrade — whether it
-- succeeded or was rolled back — without SSHing into the server.
--
-- Populated by the upgrade service at completion and at rollback. The
-- `error` column retains the short failure reason; `progress_log` carries
-- the multi-line narrative.
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN progress_log text;

COMMENT ON COLUMN public.upgrade.progress_log IS
    'Tail of the upgrade progress log (last ~50 lines). Populated on success, rollback, or direct failure by the upgrade service so operators can inspect what happened from the admin UI.';

END;
