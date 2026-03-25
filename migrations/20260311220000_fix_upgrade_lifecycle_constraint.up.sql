-- Migration 20260311220000: Fix upgrade lifecycle CHECK constraint
-- Add missing guard: cannot be both completed AND rolled back
BEGIN;

ALTER TABLE public.upgrade
    DROP CONSTRAINT upgrade_lifecycle,
    ADD CONSTRAINT upgrade_lifecycle CHECK (
        (completed_at IS NULL OR started_at IS NOT NULL) AND
        (started_at IS NULL OR scheduled_at IS NOT NULL) AND
        (skipped_at IS NULL OR completed_at IS NULL) AND
        (rollback_completed_at IS NULL OR error IS NOT NULL) AND
        (completed_at IS NULL OR error IS NULL) AND
        (rollback_completed_at IS NULL OR completed_at IS NULL)
    );

END;
