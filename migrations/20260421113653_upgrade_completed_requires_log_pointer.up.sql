-- Migration 20260421113653: upgrade_completed_requires_log_pointer
--
-- Promote LOG_POINTER_STAMPED to a DB-level CHECK:
--   state='completed' ⇒ log_relative_file_path IS NOT NULL
--
-- Previously enforced only by a Go-side fail-fast block (service.go C5).
-- The column was added 2026-04-15 (migration 20260415220000), so rows
-- completed before that date have NULL. Pre-ship check
-- (tmp/paralegal-db-invariants-preship-2026-04-21.md): 33 historical
-- rows fleet-wide across all 8 cloud servers. Backfill with a tombstone
-- sentinel, then extend chk_upgrade_state_attributes.
BEGIN;

UPDATE public.upgrade
   SET log_relative_file_path = 'unknown-pre-2026-04-15'
 WHERE state = 'completed' AND log_relative_file_path IS NULL;

ALTER TABLE public.upgrade DROP CONSTRAINT chk_upgrade_state_attributes;

ALTER TABLE public.upgrade ADD CONSTRAINT chk_upgrade_state_attributes CHECK (
CASE state
    WHEN 'available'::upgrade_state THEN ((scheduled_at IS NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (skipped_at IS NULL) AND (dismissed_at IS NULL) AND (superseded_at IS NULL))
    WHEN 'scheduled'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'in_progress'::upgrade_state THEN ((scheduled_at IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (error IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'completed'::upgrade_state THEN ((completed_at IS NOT NULL) AND (error IS NULL) AND (rolled_back_at IS NULL) AND (log_relative_file_path IS NOT NULL))
    WHEN 'failed'::upgrade_state THEN ((error IS NOT NULL) AND (started_at IS NOT NULL) AND (completed_at IS NULL) AND (rolled_back_at IS NULL))
    WHEN 'rolled_back'::upgrade_state THEN ((rolled_back_at IS NOT NULL) AND (error IS NOT NULL) AND (completed_at IS NULL))
    WHEN 'dismissed'::upgrade_state THEN ((dismissed_at IS NOT NULL) AND ((error IS NOT NULL) OR (rolled_back_at IS NOT NULL)))
    WHEN 'skipped'::upgrade_state THEN (skipped_at IS NOT NULL)
    WHEN 'superseded'::upgrade_state THEN (superseded_at IS NOT NULL)
    ELSE false
END);

COMMENT ON CONSTRAINT chk_upgrade_state_attributes ON public.upgrade IS
    'Invariant LOG_POINTER_STAMPED (state=completed arm): DB-enforced. '
    'Prior to 2026-04-21, enforced only by the Go-side C5 fail-fast block in '
    'cli/internal/upgrade/service.go. DB layer now binds any future bypass '
    'path (manual UPDATE, recovery tooling). '
    'Pre-ship: 33 historical NULL rows fleet-wide, backfilled to the '
    'sentinel ''unknown-pre-2026-04-15'' in the same migration.';

END;
