-- Revert: Fix Phase 1 stop notification, step tracking, and pipeline step weights table.

BEGIN;

-- ============================================================================
-- SECTION 1: Revert Phase 1 stop notification
-- ============================================================================

-- Restore unconditional notify_stop (original from pipeline_phase_progress migration)
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Only fires for statistical_unit_flush_staging (last Phase 1 step).
  -- Priority ordering guarantees next round's collect_changes can't run
  -- until Phase 2 finishes, so pipeline_progress won't be re-populated.
  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$procedure$;

-- ============================================================================
-- SECTION 2: Revert pipeline_progress_on_children_created — unconditionally set step
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_children_created(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id bigint,
    IN p_child_count integer
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_parent_command TEXT;
BEGIN
    SELECT command INTO v_parent_command
    FROM worker.tasks WHERE id = p_parent_task_id;

    UPDATE worker.pipeline_progress
    SET total = total + p_child_count,
        step = v_parent_command,
        updated_at = clock_timestamp()
    WHERE phase = p_phase;
END;
$procedure$;

-- ============================================================================
-- SECTION 3: Revert flush_staging worker wrapper — simple passthrough
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    CALL public.statistical_unit_flush_staging();
END;
$procedure$;

-- ============================================================================
-- SECTION 4: Drop pipeline step weights
-- ============================================================================

DROP VIEW IF EXISTS public.pipeline_step_weight;
DROP TABLE IF EXISTS worker.pipeline_step_weight;

END;
