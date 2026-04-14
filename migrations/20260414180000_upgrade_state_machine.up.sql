-- Migration 20260414180000: upgrade_state_machine
--
-- Replace state-derivation-spread-across-seven-timestamp-columns plus
-- ad-hoc UI logic (app/src/app/admin/upgrades/page.tsx:getStatus) with a
-- single authoritative state column, a CHECK constraint that makes
-- illegal attribute combinations impossible at the DB layer, and a
-- display-label function for UI.
--
-- `state` is the expression of operator / service intent. Code writes
-- state explicitly alongside the timestamp column it sets. The CHECK
-- constraint validates attributes against the declared state — so when
-- something is wrong, the error message is precise and actionable.
--
-- No transition trigger: any row whose current attribute set is valid
-- per chk_upgrade_state_attributes is a legal row, regardless of how it
-- got there. Operators can hand-edit rows to recover state without
-- fighting a forward-only state machine.
BEGIN;

-- 1. Enum type for upgrade lifecycle states. Follows the "_state" suffix
--    convention used by import_job_state / import_data_state in this
--    project (state-machine enums go unsuffixed with "_type").
CREATE TYPE public.upgrade_state AS ENUM (
    'available',   -- discovered, nothing done yet
    'scheduled',   -- enqueued for the service to pick up
    'in_progress', -- executeUpgrade running
    'completed',   -- terminal: success
    'failed',      -- error caught before rollback could run
    'rolled_back', -- error + rollback completed; previous version restored
    'dismissed',   -- operator acknowledged a failed/rolled_back row
    'skipped',     -- user chose not to apply an available upgrade
    'superseded'   -- terminal: a newer upgrade completed, this one obsolete
);

-- 2. dismissed_at: semantically separate from skipped_at. Dismiss is for
--    failures (operator acknowledges a failed/rolled_back row); Skip is
--    for available upgrades the user chose not to apply. The pre-split
--    UI used skipped_at for both, which lost the distinction on restore.
ALTER TABLE public.upgrade ADD COLUMN dismissed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.upgrade.dismissed_at IS
    'Timestamp when the operator dismissed (acknowledged) a failed or rolled_back upgrade. Distinct from skipped_at, which is for available upgrades the user chose not to apply.';

-- 3. Backfill dismissed_at from skipped_at where the row has failure
--    evidence — those were failure-dismissals under the old conflated
--    semantics, not user-initiated skips.
UPDATE public.upgrade
   SET dismissed_at = skipped_at,
       skipped_at   = NULL
 WHERE skipped_at IS NOT NULL
   AND (error IS NOT NULL OR rollback_completed_at IS NOT NULL);

-- 4. state column — authoritative, NOT generated, NOT NULL, code-set.
--    Code writes state on every transition; the CHECK constraint below
--    validates that the timestamp columns match the declared state.
ALTER TABLE public.upgrade ADD COLUMN state public.upgrade_state NOT NULL DEFAULT 'available';

-- 5. Backfill state from existing timestamp columns. Priority ordering
--    matches the UI's existing getStatus function
--    (app/src/app/admin/upgrades/page.tsx:86) plus the new 'dismissed'
--    bucket that wins over failed/rolled_back when dismissed_at is set.
UPDATE public.upgrade SET state = CASE
  WHEN dismissed_at          IS NOT NULL THEN 'dismissed'
  WHEN completed_at          IS NOT NULL THEN 'completed'
  WHEN superseded_at         IS NOT NULL THEN 'superseded'
  WHEN skipped_at            IS NOT NULL THEN 'skipped'
  WHEN rollback_completed_at IS NOT NULL THEN 'rolled_back'
  WHEN error                 IS NOT NULL THEN 'failed'
  WHEN started_at            IS NOT NULL THEN 'in_progress'
  WHEN scheduled_at          IS NOT NULL THEN 'scheduled'
  ELSE                                        'available'
END::public.upgrade_state;

COMMENT ON COLUMN public.upgrade.state IS
    'Authoritative upgrade lifecycle state. Code writes this explicitly on every transition. The chk_upgrade_state_attributes CHECK constraint validates that the timestamp columns match the declared state — illegal combinations are rejected at the DB layer.';

-- 5.5 Coalesce NULL errors on rolled-back rows. Some early rollbacks
--     completed without writing an error message; the 'rolled_back'
--     CHECK below requires error IS NOT NULL.
UPDATE public.upgrade
   SET error = 'Rollback completed (no error recorded)'
 WHERE rollback_completed_at IS NOT NULL AND error IS NULL;

-- 6. chk_upgrade_state_attributes — CASE state WHEN ... END per-state
--    invariants. Same idiom as chk_batch_seq_state_action (migration
--    20260131220347) and postal_locations_cannot_have_coordinates
--    (migration 20240212000000). ELSE FALSE makes any unlisted state
--    invalid.
ALTER TABLE public.upgrade
ADD CONSTRAINT chk_upgrade_state_attributes CHECK (
    CASE state
        WHEN 'available' THEN
            scheduled_at IS NULL
            AND started_at IS NULL
            AND completed_at IS NULL
            AND error IS NULL
            AND rollback_completed_at IS NULL
            AND skipped_at IS NULL
            AND dismissed_at IS NULL
            AND superseded_at IS NULL
        WHEN 'scheduled' THEN
            scheduled_at IS NOT NULL
            AND started_at IS NULL
            AND completed_at IS NULL
            AND error IS NULL
            AND rollback_completed_at IS NULL
        WHEN 'in_progress' THEN
            scheduled_at IS NOT NULL
            AND started_at IS NOT NULL
            AND completed_at IS NULL
            AND error IS NULL
            AND rollback_completed_at IS NULL
        WHEN 'completed' THEN
            completed_at IS NOT NULL
            AND error IS NULL
            AND rollback_completed_at IS NULL
        WHEN 'failed' THEN
            error IS NOT NULL
            AND started_at IS NOT NULL
            AND completed_at IS NULL
            AND rollback_completed_at IS NULL
        WHEN 'rolled_back' THEN
            rollback_completed_at IS NOT NULL
            AND error IS NOT NULL
            AND completed_at IS NULL
        WHEN 'dismissed' THEN
            dismissed_at IS NOT NULL
            AND (error IS NOT NULL OR rollback_completed_at IS NOT NULL)
        WHEN 'skipped' THEN
            skipped_at IS NOT NULL
        WHEN 'superseded' THEN
            superseded_at IS NOT NULL
        ELSE FALSE
    END
);

-- 7. PostgREST computed column: display_state(upgrade) returns a
--    human-friendly label for UI / CLI consumption. Follows the
--    display_name(upgrade) pattern from migration 20260328092344.
CREATE FUNCTION public.display_state(u public.upgrade) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE u.state
        WHEN 'available'   THEN 'Available'
        WHEN 'scheduled'   THEN 'Scheduled'
        WHEN 'in_progress' THEN 'In Progress'
        WHEN 'completed'   THEN 'Completed'
        WHEN 'failed'      THEN 'Failed'
        WHEN 'rolled_back' THEN 'Rolled Back'
        WHEN 'dismissed'   THEN 'Dismissed'
        WHEN 'skipped'     THEN 'Skipped'
        WHEN 'superseded'  THEN 'Superseded'
    END;
$$;

COMMENT ON FUNCTION public.display_state(public.upgrade) IS
'PostgREST computed column. Human-readable label for public.upgrade.state. '
'Usage: GET /rest/upgrade?select=*,display_state';

END;
