-- Migration 20260330193847: add_artifacts_ready_to_upgrade
BEGIN;

-- Track whether release artifacts (manifest, binaries, Docker images) are available.
-- Orthogonal to release_status — a prerelease can be building or ready.
-- Commits (edge channel) don't need release artifacts; they use Docker images by SHA.
ALTER TABLE public.upgrade ADD COLUMN artifacts_ready BOOLEAN NOT NULL DEFAULT false;

-- Existing commits are always ready (edge channel pulls by SHA)
UPDATE public.upgrade SET artifacts_ready = true WHERE release_status = 'commit';

-- Existing tagged releases that have completed are obviously ready
UPDATE public.upgrade SET artifacts_ready = true WHERE completed_at IS NOT NULL;

-- Clear the false "failed" status from manifest-not-ready pre-flight failures.
-- These were incorrectly marked as errors when CI hadn't finished building.
UPDATE public.upgrade
SET error = NULL, scheduled_at = NULL, started_at = NULL
WHERE error LIKE '%manifest not found%' OR error LIKE '%Release manifest not available%';

END;
