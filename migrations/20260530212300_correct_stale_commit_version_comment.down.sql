-- Down Migration 20260530212300: correct stale commit_version comment
--
-- Restore the previous (stale) comment text verbatim — exactly as carried from
-- migration 20260415120722 onto the renamed commit_version column.
BEGIN;

COMMENT ON COLUMN public.upgrade.commit_version IS
    'Output of `git describe --tags --always <commit_sha>` captured at discovery time. Used by the upgrade service to look up Docker images in GHCR without drift caused by later tags being pushed past the commit.';

END;
