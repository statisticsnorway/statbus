-- Fix Phase 1 stop notification, pipeline step tracking, and add step weights table.
--
-- Problem 1: notify_is_deriving_statistical_units_stop fires prematurely.
-- Fix: Make the stop procedure conditional — only fire if no Phase 1 tasks remain.
--
-- Problem 2: on_children_created sets step for ALL commands, but only weighted
-- pipeline steps should show in the progress bar.
-- Fix: Only set step when the parent command has a pipeline_step_weight entry.
--
-- Problem 3: flush_staging doesn't set its step in pipeline_progress.
-- Fix: Make the worker wrapper set the step before/after execution.
--
-- Pipeline step weights: Move hardcoded UI weights into the database.
-- derive_power_groups is no longer a pipeline step (removed by integration migration).
-- Two visible Phase 1 steps: derive_statistical_unit (87), statistical_unit_flush_staging (14).

BEGIN;

-- ============================================================================
-- SECTION 1: Fix Phase 1 stop notification
-- ============================================================================

-- Make notify_stop conditional: only fire if no more Phase 1 tasks are pending/running.
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
LANGUAGE plpgsql
AS $notify_is_deriving_statistical_units_stop$
BEGIN
  -- Check if any Phase 1 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 1 tasks that still need to run.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_statistical_units'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 1 work pending, don't stop yet
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$notify_is_deriving_statistical_units_stop$;

-- ============================================================================
-- SECTION 2: Pipeline step weights table
-- ============================================================================

-- Stores the relative wall-clock weight of each step within its phase.
-- Used by the frontend to compute weighted progress percentages.
-- Weights are proportional (not required to sum to 100).
CREATE TABLE worker.pipeline_step_weight (
    phase worker.pipeline_phase NOT NULL,
    step TEXT NOT NULL,
    weight INT NOT NULL CHECK (weight > 0),
    PRIMARY KEY (phase, step),
    FOREIGN KEY (step) REFERENCES worker.command_registry(command)
);

COMMENT ON TABLE worker.pipeline_step_weight IS
  'Relative wall-clock weights for pipeline steps, used by frontend progress bars. '
  'When adding a new step to a phase, add its weight here too.';

-- Phase 1 weights derived from production wall-clock times (no.statbus.org, 2026-02-24).
-- Dataset: 1.1M legal units + 826K establishments, analytics_partition_count=128.
-- derive_power_groups removed from pipeline — PG records managed during import.
INSERT INTO worker.pipeline_step_weight (phase, step, weight) VALUES
  ('is_deriving_statistical_units', 'derive_statistical_unit', 87),
  ('is_deriving_statistical_units', 'statistical_unit_flush_staging', 14);

-- Phase 2 weights from same dataset.
INSERT INTO worker.pipeline_step_weight (phase, step, weight) VALUES
  ('is_deriving_reports', 'derive_reports', 1),
  ('is_deriving_reports', 'derive_statistical_history', 2),
  ('is_deriving_reports', 'derive_statistical_unit_facet', 2),
  ('is_deriving_reports', 'statistical_unit_facet_reduce', 3),
  ('is_deriving_reports', 'derive_statistical_history_facet', 84),
  ('is_deriving_reports', 'statistical_history_facet_reduce', 9);

-- View for frontend access via PostgREST (/rest/pipeline_step_weight).
-- Read-only: the UNION ALL prevents PostgreSQL from marking it as auto-updatable.
CREATE VIEW public.pipeline_step_weight WITH (security_invoker = on) AS
SELECT phase::text, step, weight
FROM worker.pipeline_step_weight
UNION ALL
SELECT NULL, NULL, NULL WHERE false;

GRANT SELECT ON public.pipeline_step_weight TO authenticated, regular_user, admin_user;

-- Worker needs SELECT on the base table for pipeline_progress_on_children_created
-- (checks if a command has a weight entry before setting the step field).
GRANT SELECT ON worker.pipeline_step_weight TO authenticated;

-- ============================================================================
-- SECTION 3: Fix pipeline_progress_on_children_created — only set step for weighted commands
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_children_created(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id bigint,
    IN p_child_count integer
)
LANGUAGE plpgsql
AS $pipeline_progress_on_children_created$
DECLARE
    v_parent_command TEXT;
BEGIN
    -- Look up the parent command for the step field
    SELECT command INTO v_parent_command
    FROM worker.tasks WHERE id = p_parent_task_id;

    -- Only set step if the command has a pipeline_step_weight entry
    -- (non-weighted commands like statistical_unit_refresh_batch should not overwrite step)
    IF EXISTS (SELECT 1 FROM worker.pipeline_step_weight WHERE step = v_parent_command AND phase = p_phase) THEN
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            step = v_parent_command,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    ELSE
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    END IF;
END;
$pipeline_progress_on_children_created$;

-- ============================================================================
-- SECTION 4: Fix flush_staging worker wrapper — set step before/after
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_flush_staging$
BEGIN
    -- Set step to flush_staging so progress bar shows correct phase
    UPDATE worker.pipeline_progress
    SET step = 'statistical_unit_flush_staging', updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM pg_notify('pipeline_progress', '');

    CALL public.statistical_unit_flush_staging();

    -- Mark phase complete
    UPDATE worker.pipeline_progress
    SET completed = total, updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM pg_notify('pipeline_progress', '');
END;
$statistical_unit_flush_staging$;

END;
