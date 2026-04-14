-- Migration 20260414170000: split_artifacts_ready_into_images_and_release
--
-- Before: `public.upgrade.artifacts_ready` was a single stored boolean,
-- maintained optimistically (hardcoded true for commits at insert time)
-- and conflated two independent CI workflows — ci-images.yaml (Docker
-- images) and release.yaml (sb binary + manifest + GitHub Release).
--
-- After: two source-of-truth columns + one generated composite.
--
--   docker_images_ready    — set true by the upgrade service discovery
--                            cycle when `docker manifest inspect` resolves
--                            all four images (db/app/worker/proxy) at the
--                            runtime VERSION tag.
--   release_builds_ready   — set true when FetchManifest(tag) succeeds for
--                            a tagged release. Pre-set true for commits —
--                            edge channel does not use release artifacts.
--   artifacts_ready        — BOOLEAN GENERATED ALWAYS AS (...) STORED.
--                            Derived by the DB at write time; never drifts.
--                            Appears in select=* automatically and is
--                            indexable when we later need WHERE filters.
--
-- Choice of GENERATED STORED over a PostgREST row function follows the
-- project convention (GENERATED STORED is already used in `region`,
-- `tag`, `settings`, `statistical_unit_facet`, and several other tables),
-- and Go service code at cli/internal/upgrade/service.go:424 already
-- filters `WHERE NOT artifacts_ready`, which an index can accelerate on
-- a stored column.
BEGIN;

-- 1. New source-of-truth columns
ALTER TABLE public.upgrade
    ADD COLUMN docker_images_ready  BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN release_builds_ready BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.upgrade.docker_images_ready IS
    'Docker images (db/app/worker/proxy) exist in the registry at the runtime VERSION tag. Set by the upgrade service discovery cycle via docker manifest inspect.';
COMMENT ON COLUMN public.upgrade.release_builds_ready IS
    'Release builds (sb binary + manifest.json + GitHub Release entry) exist for a tagged release. Commits have this pre-set true since edge channel does not need release builds.';

-- 2. Backfill from the existing stored flag, preserving legacy semantics.
--    artifacts_ready=true previously meant either "tagged release manifest
--    landed" or "commit (optimistic, assumed ready)". Either way, treat
--    both new source-of-truth columns as true; discovery will re-verify
--    and correct if images turn out to be missing.
UPDATE public.upgrade
   SET docker_images_ready = true,
       release_builds_ready = true
 WHERE artifacts_ready = true;

-- 3. Commits never need release builds — pre-set true so artifacts_ready
--    only gates on docker_images_ready for edge channel. (The backfill
--    above already covered commits that previously had artifacts_ready=true;
--    this catches any commit rows with artifacts_ready=false.)
UPDATE public.upgrade
   SET release_builds_ready = true
 WHERE release_status = 'commit'
   AND NOT release_builds_ready;

-- 4. Drop the stored (and code-maintained) composite, then re-add it as a
--    generated column derived from the two source-of-truth columns. PG
--    computes it at write time; no code path maintains it.
ALTER TABLE public.upgrade DROP COLUMN artifacts_ready;

ALTER TABLE public.upgrade ADD COLUMN artifacts_ready BOOLEAN
    GENERATED ALWAYS AS (docker_images_ready AND release_builds_ready) STORED;

COMMENT ON COLUMN public.upgrade.artifacts_ready IS
    'Composite ready flag, GENERATED STORED from docker_images_ready AND release_builds_ready. True when both levels of CI output are published and the upgrade is safe to start. Indexable; appears in select=* automatically.';

END;
