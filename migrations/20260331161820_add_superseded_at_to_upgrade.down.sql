-- Down Migration 20260331161820: add_superseded_at_to_upgrade
BEGIN;

-- Reverse: move superseded_at back to skipped_at
UPDATE public.upgrade
   SET skipped_at = superseded_at
 WHERE superseded_at IS NOT NULL AND skipped_at IS NULL;

ALTER TABLE public.upgrade DROP COLUMN superseded_at;

END;
