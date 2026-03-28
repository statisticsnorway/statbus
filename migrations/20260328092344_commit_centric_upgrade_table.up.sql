-- Migration 20260328092344: commit_centric_upgrade_table
-- Drop the version-centric upgrade table and recreate with commit-centric model.
-- No stable release has been made, so we can drop and recreate cleanly.
BEGIN;

-- Drop triggers first (they depend on the table)
DROP TRIGGER IF EXISTS upgrade_notify_daemon_trigger ON public.upgrade;
DROP TRIGGER IF EXISTS upgrade_notify_frontend_trigger ON public.upgrade;

-- Drop the old table (CASCADE drops RLS policies, constraints, indexes)
DROP TABLE IF EXISTS public.upgrade CASCADE;

-- Drop functions that referenced the old schema
DROP FUNCTION IF EXISTS public.upgrade_notify_daemon();
DROP FUNCTION IF EXISTS public.upgrade_notify_frontend();
DROP FUNCTION IF EXISTS public.upgrade_request_check();

-- Drop the upgrade_channel enum (no longer needed — tags[] replaces it)
DROP TYPE IF EXISTS public.upgrade_channel;

-- Enum for release status (replaces is_release + is_prerelease booleans)
CREATE TYPE public.release_status_type AS ENUM ('commit', 'prerelease', 'release');

-- New commit-centric schema
CREATE TABLE public.upgrade (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    commit_sha TEXT NOT NULL UNIQUE,
    committed_at TIMESTAMPTZ NOT NULL,
    position INTEGER,
    tags TEXT[] NOT NULL DEFAULT '{}',
    release_status public.release_status_type NOT NULL DEFAULT 'commit',
    summary TEXT NOT NULL,
    changes TEXT,
    release_url TEXT,
    has_migrations BOOLEAN NOT NULL DEFAULT FALSE,
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error TEXT,
    rollback_completed_at TIMESTAMPTZ,
    skipped_at TIMESTAMPTZ,
    from_version TEXT,
    images_downloaded BOOLEAN NOT NULL DEFAULT FALSE,
    backup_path TEXT
);

COMMENT ON TABLE public.upgrade IS
    'Commit-centric software upgrade lifecycle. Each row is a commit (which may '
    'also be a tagged release). Populated by upgrade daemon, managed by admin. '
    'tags[] holds git tags on this commit (e.g. v0.78.0-rc.1). '
    'release_status derived from tags: commit (no release tag), prerelease, or release. '
    'To accept: SET scheduled_at. To unschedule: SET scheduled_at = NULL. '
    'To retry after failure: SET started_at = NULL, error = NULL, scheduled_at = now().';

-- RLS: admin can manage, authenticated can view
ALTER TABLE public.upgrade ENABLE ROW LEVEL SECURITY;

CREATE POLICY upgrade_admin_manage ON public.upgrade
    FOR ALL TO admin_user
    USING (true) WITH CHECK (true);

CREATE POLICY upgrade_authenticated_view ON public.upgrade
    FOR SELECT TO authenticated
    USING (true);

-- Table-level GRANTs (required alongside RLS for PostgREST access)
GRANT SELECT ON public.upgrade TO authenticated;
GRANT SELECT ON public.upgrade TO regular_user;
GRANT ALL ON public.upgrade TO admin_user;

-- PostgREST computed column: best display name for a commit
CREATE FUNCTION public.display_name(u public.upgrade)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
    u.tags[array_upper(u.tags, 1)],
    'sha-' || left(u.commit_sha, 12)
  );
$$;

COMMENT ON FUNCTION public.display_name(public.upgrade) IS
'PostgREST computed column. Returns the best display name: '
'stable tag > last tag > short SHA. '
'Usage: GET /rest/upgrade?select=*,display_name';

-- Trigger: notify daemon when scheduled_at is set (sends commit_sha as payload)
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_notify_daemon$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    PERFORM pg_notify('upgrade_apply', NEW.commit_sha);
  END IF;
  RETURN NEW;
END;
$upgrade_notify_daemon$;

CREATE TRIGGER upgrade_notify_daemon_trigger
  AFTER UPDATE ON public.upgrade
  FOR EACH ROW
  EXECUTE FUNCTION public.upgrade_notify_daemon();

-- Trigger: notify frontend on any upgrade row change
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

-- RPC function: request an upgrade check (sends NOTIFY, schema-independent)
CREATE FUNCTION public.upgrade_request_check()
RETURNS void LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_request_check$
  NOTIFY upgrade_check;
$upgrade_request_check$;

END;
