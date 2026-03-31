-- Migration 20260331161820: add_superseded_at_to_upgrade
BEGIN;

ALTER TABLE public.upgrade ADD COLUMN superseded_at TIMESTAMPTZ;

-- Migrate existing data: rows auto-skipped by the upgrade service → superseded.
-- skipped_at is reserved for user-initiated skips (via the admin UI).
UPDATE public.upgrade
   SET superseded_at = skipped_at,
       skipped_at = NULL
 WHERE skipped_at IS NOT NULL;

END;
