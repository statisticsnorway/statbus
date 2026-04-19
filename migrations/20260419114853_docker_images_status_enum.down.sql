-- Down migration: revert docker_images_status enum back to docker_images_ready boolean

BEGIN;

-- Add back the boolean column
ALTER TABLE public.upgrade ADD COLUMN docker_images_ready boolean NOT NULL DEFAULT false;

-- Data migration: enum → boolean
UPDATE public.upgrade SET docker_images_ready = (docker_images_status = 'ready');

-- Drop the enum column and type
ALTER TABLE public.upgrade DROP COLUMN docker_images_status;
DROP TYPE IF EXISTS public.docker_images_status_type;

END;
