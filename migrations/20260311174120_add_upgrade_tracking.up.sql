-- Migration 20260311174120: Add upgrade tracking tables
BEGIN;

-- Upgrade channel controls what the daemon discovers
CREATE TYPE public.upgrade_channel AS ENUM ('stable', 'prerelease', 'pinned');

COMMENT ON TYPE public.upgrade_channel IS
    'Controls upgrade discovery: stable = only stable releases, '
    'prerelease = include pre-releases, pinned = no discovery (manual only).';

-- Upgrade lifecycle table
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
    CONSTRAINT upgrade_version_unique UNIQUE (version),
    CONSTRAINT upgrade_lifecycle CHECK (
        (completed_at IS NULL OR started_at IS NOT NULL) AND
        (started_at IS NULL OR scheduled_at IS NOT NULL) AND
        (skipped_at IS NULL OR completed_at IS NULL) AND
        (rollback_completed_at IS NULL OR error IS NOT NULL) AND
        (completed_at IS NULL OR error IS NULL)
    )
);

COMMENT ON TABLE public.upgrade IS
    'Software upgrade lifecycle. Populated by upgrade daemon, managed by admin. '
    'summary = release title; changes = full commit log since prior version. '
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

-- System info key-value store
CREATE TABLE public.system_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE public.system_info IS
    'System-wide configuration key-value store. '
    'Used for upgrade channel, current version, etc.';

ALTER TABLE public.system_info ENABLE ROW LEVEL SECURITY;

CREATE POLICY system_info_admin_manage ON public.system_info
    FOR ALL TO admin_user
    USING (true) WITH CHECK (true);

CREATE POLICY system_info_authenticated_view ON public.system_info
    FOR SELECT TO authenticated
    USING (true);

-- Seed default system info
INSERT INTO public.system_info (key, value) VALUES
    ('upgrade_channel', 'stable'),
    ('upgrade_check_interval', '6h'),
    ('upgrade_auto_download', 'true');

END;
