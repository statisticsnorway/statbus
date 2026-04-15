-- Migration 20260415230000: drop_artifacts_ready_column
--
-- `artifacts_ready` was a GENERATED ALWAYS AS (docker_images_ready AND release_builds_ready) STORED
-- convenience column. All consumers have been updated to reference the two source-of-truth columns
-- directly, so the derived column is redundant overhead. Dropping it:
--   - simplifies the schema (one fewer column to reason about)
--   - removes the verifyArtifacts WHERE clause dependency on a generated column
--   - the UI gate now evaluates the two columns inline

BEGIN;

ALTER TABLE public.upgrade DROP COLUMN artifacts_ready;

END;
