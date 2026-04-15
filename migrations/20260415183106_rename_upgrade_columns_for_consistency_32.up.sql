-- Rename 4 columns in public.upgrade for naming consistency.
-- See tmp/paralegal-upgrade-column-audit-2026-04-15.md for full rationale.
--
-- 1. rollback_completed_at → rolled_back_at
--    All other state-transition timestamps use <past-tense-state>_at.
--    This was the only one with a noun prefix (rollback_) and infix (_completed).
--    No rollback_started_at exists, so _completed is redundant.
--
-- 2. images_downloaded → docker_images_downloaded
--    Omitted "docker" (inconsistent with docker_images_ready).
--    Makes the pair (docker_images_downloaded, docker_images_ready) clearly
--    distinct steps in the same pipeline.
--
-- 3. discover_version_tag → version
--    The old name encoded when it was captured (discover_) rather than what
--    it stores (the human-readable version string, e.g. "v2026.03.1").
--
-- 4. position → topological_order
--    Generic single word; topological_order is self-documenting.
BEGIN;

ALTER TABLE public.upgrade RENAME COLUMN rollback_completed_at TO rolled_back_at;
ALTER TABLE public.upgrade RENAME COLUMN images_downloaded TO docker_images_downloaded;
ALTER TABLE public.upgrade RENAME COLUMN discover_version_tag TO version;
ALTER TABLE public.upgrade RENAME COLUMN position TO topological_order;

END;
