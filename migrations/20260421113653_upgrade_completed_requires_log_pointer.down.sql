-- Down Migration 20260421113653: upgrade_completed_requires_log_pointer
--
-- Restore the prior chk_upgrade_state_attributes body verbatim (without
-- the log_relative_file_path clause on the 'completed' arm).
-- Does NOT revert the backfill UPDATE — sentinel rows stay tagged.
BEGIN;

ALTER TABLE public.upgrade DROP CONSTRAINT chk_upgrade_state_attributes;

ALTER TABLE public.upgrade ADD CONSTRAINT chk_upgrade_state_attributes CHECK (
CASE state
    WHEN 'available'::upgrade_state THEN ((scheduled_at IS NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (skipped_at IS NULL) AND (dismissed_at IS NULL) AND (superseded_at IS NULL))
    WHEN 'scheduled'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'in_progress'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'completed'::upgrade_state THEN ((completed_at IS NOT NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'failed'::upgrade_state THEN ((error IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'rolled_back'::upgrade_state THEN ((rolled_back_at IS NOT NULL) AND (error IS NOT NULL) AND (completed_at IS NULL))
    WHEN 'dismissed'::upgrade_state THEN ((dismissed_at IS NOT NULL) AND ((error IS NOT NULL) OR (rolled_back_at IS NOT NULL)))
    WHEN 'skipped'::upgrade_state THEN (skipped_at IS NOT NULL)
    WHEN 'superseded'::upgrade_state THEN (superseded_at IS NOT NULL)
    ELSE false
END);

END;
