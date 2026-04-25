-- Migration 20260425163029: dismiss_corrupt_upgrade_lifecycle_rows
--
-- Pre-rc.63 lifecycle bugs left some public.upgrade rows in pre-terminal
-- states ('available', 'scheduled', 'in_progress') with timestamp columns
-- inconsistent with the chk_upgrade_state_attributes predicate for that
-- state — e.g., state='available' with started_at populated. These rows
-- pre-date the constraint enforcement; they were either inserted before
-- the constraint existed (migration 20260414180000 created the table) or
-- via a path that briefly bypassed it (the rc.63 relaxation in
-- 20260424160235 did not reverse the prior contamination).
--
-- Symptom: markCIImagesFailed (cli/internal/upgrade/service.go) UPDATE
-- re-validates the full row against the constraint and fails with
-- SQLSTATE 23514. The CI failure-detection invariant fires every
-- discovery cycle (observed on statbus_demo running rc.65 on
-- 2026-04-25 — two shas: e1fe8456, e23556347f81).
--
-- Repair: move every corrupt pre-terminal row to state='dismissed' with
-- dismissed_at=NOW() and a backfill marker in `error`. The dismissed arm
-- of chk_upgrade_state_attributes only requires
--     dismissed_at IS NOT NULL AND (error IS NOT NULL OR rolled_back_at IS NOT NULL)
-- so this UPDATE always satisfies the constraint regardless of the
-- corrupt timestamp columns left over from the prior bug.
--
-- Idempotent: the WHERE clause matches only constraint-violating rows.
-- After the migration runs, no rows match. Safe to re-run.
--
-- Companion: a code-side silent-skip branch in
-- cli/internal/upgrade/service.go:markCIImagesFailed catches the
-- SQLSTATE 23514 + chk_upgrade_state_attributes shape and avoids
-- escalating to CI_FAILURE_DETECTED_TRANSITIONS_ROW /
-- SERVICE_STUCK_RETRY_LOOP for the corrupt-historical-row case. The
-- migration removes the underlying rows; the code-side guard keeps any
-- future bypass path from spinning.

BEGIN;

UPDATE public.upgrade
   SET state         = 'dismissed',
       dismissed_at  = COALESCE(dismissed_at, NOW()),
       error         = COALESCE(
                           error,
                           'backfill: pre-rc.63 lifecycle inconsistency '
                           '(state/timestamp mismatch swept by migration '
                           '20260425163029_dismiss_corrupt_upgrade_lifecycle_rows)'
                       )
 WHERE
    (state = 'available'   AND (
         scheduled_at  IS NOT NULL
      OR started_at    IS NOT NULL
      OR completed_at  IS NOT NULL
      OR rolled_back_at IS NOT NULL
      OR skipped_at    IS NOT NULL
      OR dismissed_at  IS NOT NULL
      OR superseded_at IS NOT NULL))
 OR (state = 'scheduled'   AND (
         scheduled_at  IS NULL
      OR started_at    IS NOT NULL
      OR completed_at  IS NOT NULL
      OR rolled_back_at IS NOT NULL))
 OR (state = 'in_progress' AND (
         scheduled_at  IS NULL
      OR started_at    IS NULL
      OR completed_at  IS NOT NULL
      OR rolled_back_at IS NOT NULL));

COMMIT;
