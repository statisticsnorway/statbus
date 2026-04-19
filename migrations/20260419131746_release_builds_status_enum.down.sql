-- Down migration: revert release_builds_status enum back to release_builds_ready boolean

BEGIN;

-- Add back the boolean column
ALTER TABLE public.upgrade ADD COLUMN release_builds_ready boolean NOT NULL DEFAULT false;

-- Data migration: enum → boolean
UPDATE public.upgrade SET release_builds_ready = (release_builds_status = 'ready');

-- Drop the enum column and type
ALTER TABLE public.upgrade DROP COLUMN release_builds_status;
DROP TYPE IF EXISTS public.release_builds_status_type;

END;
