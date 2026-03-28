-- Down Migration 20260328092344: commit_centric_upgrade_table
-- Restore the old version-centric upgrade table and all dependent objects.
BEGIN;

-- Drop triggers on the new table
DROP TRIGGER IF EXISTS upgrade_notify_daemon_trigger ON public.upgrade;
DROP TRIGGER IF EXISTS upgrade_notify_frontend_trigger ON public.upgrade;

-- Drop the new table
DROP TABLE IF EXISTS public.upgrade CASCADE;

-- Drop functions
DROP FUNCTION IF EXISTS public.upgrade_notify_daemon();
DROP FUNCTION IF EXISTS public.upgrade_notify_frontend();
DROP FUNCTION IF EXISTS public.upgrade_request_check();

-- Restore upgrade_channel enum (with 'edge' value from migration 20260326161813)
CREATE TYPE public.upgrade_channel AS ENUM ('stable', 'prerelease', 'pinned', 'edge');

COMMENT ON TYPE public.upgrade_channel IS
    'Controls upgrade discovery: stable = only stable releases, '
    'prerelease = include pre-releases, pinned = no discovery (manual only).';

-- Restore old version-centric table
CREATE TABLE public.upgrade (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    version TEXT NOT NULL,
    commit_sha TEXT NOT NULL,
    is_prerelease BOOLEAN NOT NULL DEFAULT FALSE,
    summary TEXT NOT NULL,
    changes TEXT,
    release_url TEXT,
    has_migrations BOOLEAN NOT NULL DEFAULT FALSE,
    from_version TEXT,
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error TEXT,
    rollback_completed_at TIMESTAMPTZ,
    skipped_at TIMESTAMPTZ,
    images_downloaded BOOLEAN NOT NULL DEFAULT FALSE,
    backup_path TEXT,
    published_at TIMESTAMPTZ,
    CONSTRAINT upgrade_version_unique UNIQUE (version),
    CONSTRAINT upgrade_lifecycle CHECK (
        (completed_at IS NULL OR started_at IS NOT NULL) AND
        (started_at IS NULL OR scheduled_at IS NOT NULL) AND
        (skipped_at IS NULL OR completed_at IS NULL) AND
        (rollback_completed_at IS NULL OR error IS NOT NULL) AND
        (completed_at IS NULL OR error IS NULL) AND
        (rollback_completed_at IS NULL OR completed_at IS NULL)
    )
);

COMMENT ON TABLE public.upgrade IS
    'Software upgrade lifecycle. Populated by upgrade daemon, managed by admin. '
    'summary = release title; changes = full commit log since prior version. '
    'To accept: SET scheduled_at. To unschedule: SET scheduled_at = NULL. '
    'To retry after failure: SET started_at = NULL, error = NULL, scheduled_at = now().';

-- RLS
ALTER TABLE public.upgrade ENABLE ROW LEVEL SECURITY;

CREATE POLICY upgrade_admin_manage ON public.upgrade
    FOR ALL TO admin_user
    USING (true) WITH CHECK (true);

CREATE POLICY upgrade_authenticated_view ON public.upgrade
    FOR SELECT TO authenticated
    USING (true);

-- GRANTs
GRANT SELECT ON public.upgrade TO authenticated;
GRANT SELECT ON public.upgrade TO regular_user;
GRANT ALL ON public.upgrade TO admin_user;

-- Restore trigger functions (with search_path from migration 20260326174816)
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    PERFORM pg_notify('upgrade_apply', NEW.version);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

CREATE TRIGGER upgrade_notify_daemon_trigger
  AFTER UPDATE ON public.upgrade
  FOR EACH ROW
  EXECUTE FUNCTION public.upgrade_notify_daemon();

CREATE OR REPLACE FUNCTION public.upgrade_notify_frontend()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_frontend$
BEGIN
  PERFORM pg_notify('worker_status', '{"type":"upgrade_changed"}');
  RETURN COALESCE(NEW, OLD);
END;
$upgrade_notify_frontend$;

CREATE TRIGGER upgrade_notify_frontend_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.upgrade
  FOR EACH ROW
  EXECUTE FUNCTION public.upgrade_notify_frontend();

-- Restore RPC function
CREATE FUNCTION public.upgrade_request_check()
RETURNS void LANGUAGE sql SECURITY DEFINER
AS $upgrade_request_check$
  NOTIFY upgrade_check;
$upgrade_request_check$;

END;
