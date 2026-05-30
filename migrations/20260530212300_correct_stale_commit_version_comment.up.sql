-- Migration 20260530212300: correct stale commit_version comment
--
-- The public.upgrade.commit_version column's comment STALE-ly claims this column
-- is the Docker-image lookup key in GHCR. That WAS true when the column was named
-- discover_version_tag (added 20260415120722); the comment was carried verbatim
-- by Postgres across the renames discover_version_tag -> version (20260415183106)
-- -> commit_version (20260424160235).
--
-- Since rc.63 the image lookup uses commit_short, NOT this column: verifyArtifacts
-- builds the `docker manifest inspect` tag via `tag := ShortForDisplay(r.sha)`
-- (cli/internal/upgrade/service.go), deterministic from commit_sha. commit_version
-- is discovery/display metadata only.
--
-- Correct the comment so the schema (and its generated doc/db/ dump) no longer
-- misleads. Comment-only change: no column, constraint, index, or data change.
BEGIN;

COMMENT ON COLUMN public.upgrade.commit_version IS
    'Output of `git describe --tags --always <commit_sha>` captured at discovery — the human-readable version label used for display/listing of upgrades. NOTE: Docker image lookup uses commit_short (derived from commit_sha), NOT this column (see verifyArtifacts; changed in rc.63).';

END;
