-- Migration 20260419114853: Replace docker_images_ready boolean with enum
--
-- Three states: building (CI in progress), ready (images verified), failed (CI failed).
-- The boolean only distinguished "not yet" from "yes" — operators seeing
-- "images building..." had no way to know if CI had actually failed.

BEGIN;

-- Create the enum type
CREATE TYPE public.docker_images_status_type AS ENUM ('building', 'ready', 'failed');

-- Add the new column with default
ALTER TABLE public.upgrade ADD COLUMN docker_images_status public.docker_images_status_type
    NOT NULL DEFAULT 'building'::public.docker_images_status_type;

-- Data migration: copy boolean state into the new enum column
UPDATE public.upgrade SET docker_images_status = CASE
    WHEN docker_images_ready THEN 'ready'::public.docker_images_status_type
    ELSE 'building'::public.docker_images_status_type
END;

-- Drop the old boolean column and its NOT NULL constraint
ALTER TABLE public.upgrade DROP COLUMN docker_images_ready;

-- Rename the new column to take the old name's semantic role
-- (keeping docker_images_status as the name — clearer than docker_images_ready for a 3-state)
COMMENT ON COLUMN public.upgrade.docker_images_status IS
    'Docker image build status: building (CI in progress), ready (images verified in registry), '
    'failed (CI workflow failed). Checked by the upgrade service via docker manifest inspect '
    'and GitHub Actions API.';

END;
