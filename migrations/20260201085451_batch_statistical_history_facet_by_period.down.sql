-- Down Migration: Revert to processing all periods in one transaction
BEGIN;

-- ============================================================================
-- Part 1: Remove the command registration
-- ============================================================================
DELETE FROM worker.command_registry 
WHERE command = 'derive_statistical_history_facet_period';


-- ============================================================================
-- Part 2: Drop the new functions/procedures
-- ============================================================================
DROP PROCEDURE IF EXISTS worker.derive_statistical_history_facet_period(JSONB);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_history_facet_period(public.history_resolution, integer, integer);


-- ============================================================================
-- Part 3: Drop the deduplication index
-- ============================================================================
DROP INDEX IF EXISTS worker.idx_tasks_derive_history_facet_period_dedup;


-- ============================================================================
-- Part 4: Restore original derive_statistical_history_facet procedure
-- ============================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  PERFORM public.statistical_history_facet_derive(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
  -- This is the last phase, no more tasks to enqueue
END;
$derive_statistical_history_facet$;

END;
