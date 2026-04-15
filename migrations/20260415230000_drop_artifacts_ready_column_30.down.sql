-- Down migration 20260415230000: drop_artifacts_ready_column_30
--
-- Restores the GENERATED ALWAYS AS derived column that was dropped in the up migration.

BEGIN;

ALTER TABLE public.upgrade ADD COLUMN artifacts_ready BOOLEAN
    GENERATED ALWAYS AS (docker_images_ready AND release_builds_ready) STORED;

COMMENT ON COLUMN public.upgrade.artifacts_ready IS
    'Composite ready flag, GENERATED STORED from docker_images_ready AND release_builds_ready. True when both levels of CI output are published and the upgrade is safe to start. Indexable; appears in select=* automatically.';

END;
