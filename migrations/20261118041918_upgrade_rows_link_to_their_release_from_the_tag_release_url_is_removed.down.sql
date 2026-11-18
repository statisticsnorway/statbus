-- Down Migration 20261118041918: upgrade rows link to their release from the tag; release_url is removed
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN release_url TEXT;

END;
