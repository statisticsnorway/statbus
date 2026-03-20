BEGIN;

-- Reverse: drop new columns, rename back to old names
ALTER TABLE worker.tasks DROP COLUMN IF EXISTS process_stop_at;
ALTER TABLE worker.tasks DROP COLUMN IF EXISTS completion_duration_ms;
ALTER TABLE worker.tasks RENAME COLUMN process_start_at TO processed_at;
ALTER TABLE worker.tasks RENAME COLUMN process_duration_ms TO duration_ms;

-- Restore old view
DROP VIEW IF EXISTS public.worker_task;
CREATE VIEW public.worker_task
WITH (security_invoker = on)
AS
SELECT t.id,
    t.command,
    t.priority,
    t.state,
    t.parent_id,
    t.depth,
    t.child_mode,
    t.created_at,
    t.processed_at,
    t.completed_at,
    t.duration_ms,
    t.error,
    t.scheduled_at,
    t.worker_pid,
    t.payload,
    cr.queue,
    cr.description AS command_description
FROM worker.tasks AS t
JOIN worker.command_registry AS cr ON cr.command = t.command;

-- Restore derive_statistical_unit handler to use processed_at
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_power_group_id_ranges int4multirange = (payload->>'power_group_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
    v_task_id BIGINT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;
    PERFORM worker.derive_statistical_unit(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_power_group_id_ranges := v_power_group_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_round_priority_base := v_round_priority_base
    );
END;
$procedure$;

-- NOTE: process_tasks and complete_parent_if_ready are not restored here
-- because the down migration for the previous migration
-- (20260317060914_convert_pipeline_to_serial_child_tree) would need to run
-- first, restoring its own version. Column names in those procedures must
-- match the table, so this ordering is correct.

END;
