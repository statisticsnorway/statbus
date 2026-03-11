-- Down Migration 20260311220000: Revert to original lifecycle constraint
BEGIN;

ALTER TABLE public.upgrade
    DROP CONSTRAINT upgrade_lifecycle,
    ADD CONSTRAINT upgrade_lifecycle CHECK (
        (completed_at IS NULL OR started_at IS NOT NULL) AND
        (started_at IS NULL OR scheduled_at IS NOT NULL) AND
        (skipped_at IS NULL OR completed_at IS NULL) AND
        (rollback_completed_at IS NULL OR error IS NOT NULL) AND
        (completed_at IS NULL OR error IS NULL)
    );

END;
