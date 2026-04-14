-- Down migration 20260414170000: split_artifacts_ready_into_images_and_release
--
-- Restores the stored (code-maintained) `artifacts_ready` column from the
-- composite GENERATED STORED value; then drops the two source-of-truth
-- columns.
BEGIN;

-- Capture the composite into a plain BOOLEAN before dropping the source columns
ALTER TABLE public.upgrade DROP COLUMN artifacts_ready;

ALTER TABLE public.upgrade ADD COLUMN artifacts_ready BOOLEAN NOT NULL DEFAULT false;

UPDATE public.upgrade
   SET artifacts_ready = (docker_images_ready AND release_builds_ready);

ALTER TABLE public.upgrade
    DROP COLUMN release_builds_ready,
    DROP COLUMN docker_images_ready;

END;
