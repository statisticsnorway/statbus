-- Migration 20260415120722: add_discover_version_tag_to_upgrade
--
-- `verifyArtifacts` uses `git describe --tags --always <sha>` to construct
-- the Docker image tag for manifest inspection. This dynamic call drifts as
-- new tags are pushed past old commits: a commit described as
-- `v2026.03.1-rc.5-3-gc4bbd8a` at CI time may later be described as
-- `v2026.04.0-rc.6-15-gc4bbd8a`, making the manifest lookup fail forever
-- even though the images exist under the original tag name.
--
-- Fix: store the git-describe output at discover/insert time so verifyArtifacts
-- uses the stable name. NULL for rows predating this migration; verifyArtifacts
-- falls back to the dynamic call for those to preserve existing behaviour.
BEGIN;

ALTER TABLE public.upgrade
    ADD COLUMN discover_version_tag TEXT;

COMMENT ON COLUMN public.upgrade.discover_version_tag IS
    'Output of `git describe --tags --always <commit_sha>` captured at discovery time. Used by the upgrade service to look up Docker images in GHCR without drift caused by later tags being pushed past the commit.';

END;
