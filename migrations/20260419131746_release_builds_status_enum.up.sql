-- Migration 20260419131746: Replace release_builds_ready boolean with enum
--
-- Same pattern as docker_images_status_type (20260419114853):
-- Three states: building (release.yaml in progress), ready (manifest verified),
-- failed (release.yaml failed). The boolean only distinguished "not yet" from
-- "yes" — operators had no way to tell if the release workflow had failed.
--
-- For commits (edge channel), release builds are not applicable — they default
-- to 'ready' because edge doesn't use release artifacts (no sb binary, no manifest).

BEGIN;

-- Create the enum type
CREATE TYPE public.release_builds_status_type AS ENUM ('building', 'ready', 'failed');

-- Add the new column with default
ALTER TABLE public.upgrade ADD COLUMN release_builds_status public.release_builds_status_type
    NOT NULL DEFAULT 'building'::public.release_builds_status_type;

-- Data migration: copy boolean state into the new enum column
UPDATE public.upgrade SET release_builds_status = CASE
    WHEN release_builds_ready THEN 'ready'::public.release_builds_status_type
    ELSE 'building'::public.release_builds_status_type
END;

-- Drop the old boolean column
ALTER TABLE public.upgrade DROP COLUMN release_builds_ready;

COMMENT ON COLUMN public.upgrade.release_builds_status IS
    'Release build status: building (release.yaml in progress), ready (GitHub Release + sb binary + manifest verified), '
    'failed (release workflow failed). For commits (edge channel) this defaults to ready since '
    'edge does not use release artifacts. Checked by the upgrade service via FetchManifest '
    'and GitHub Actions API.';

END;
