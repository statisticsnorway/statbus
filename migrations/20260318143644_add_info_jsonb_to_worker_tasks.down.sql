BEGIN;

-- Restore collect_changes without info writing
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $command_collect_changes$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_round_priority_base BIGINT;
    v_task_id BIGINT;
    v_phase1_id BIGINT;
    v_phase2_id BIGINT;
    v_payload JSONB;
BEGIN
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_pg_ids := v_pg_ids + v_row.power_group_ids;
        v_valid_range := v_valid_range + v_row.valid_ranges;
    END LOOP;

    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- Get own task_id and round_priority_base
        SELECT id, priority INTO v_task_id, v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        -- Common payload for date-range-only children
        v_payload := jsonb_build_object(
            'valid_from', v_valid_from,
            'valid_until', v_valid_until,
            'round_priority_base', v_round_priority_base
        );

        -- =====================================================================
        -- Phase 1: derive_units_phase (serial children of collect_changes)
        -- =====================================================================
        v_phase1_id := worker.spawn(
            p_command => 'derive_units_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- derive_statistical_unit: child of phase1 (its handler spawns concurrent batch grandchildren)
        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', v_est_ids::text,
                'legal_unit_id_ranges', v_lu_ids::text,
                'enterprise_id_ranges', v_ent_ids::text,
                'power_group_id_ranges', v_pg_ids::text,
                'valid_from', v_valid_from,
                'valid_until', v_valid_until,
                'round_priority_base', v_round_priority_base
            ),
            p_parent_id => v_phase1_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- statistical_unit_flush_staging: serial sibling after derive_statistical_unit
        PERFORM worker.spawn(
            p_command => 'statistical_unit_flush_staging',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- =====================================================================
        -- Phase 2: derive_reports_phase (serial children of collect_changes)
        -- =====================================================================
        v_phase2_id := worker.spawn(
            p_command => 'derive_reports_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- derive_statistical_history: spawns concurrent period children in its handler
        PERFORM worker.spawn(
            p_command => 'derive_statistical_history',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- statistical_history_reduce: leaf
        PERFORM worker.spawn(
            p_command => 'statistical_history_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- derive_statistical_unit_facet: spawns concurrent partition children in its handler
        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- statistical_unit_facet_reduce: leaf
        PERFORM worker.spawn(
            p_command => 'statistical_unit_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- derive_statistical_history_facet: spawns concurrent period children in its handler
        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );

        -- statistical_history_facet_reduce: terminal leaf
        PERFORM worker.spawn(
            p_command => 'statistical_history_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_priority => v_round_priority_base,
            p_child_mode => 'serial'
        );
    ELSE
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$command_collect_changes$;

-- Recreate view without info column
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
    t.process_start_at,
    t.process_stop_at,
    t.completed_at,
    t.process_duration_ms,
    t.completion_duration_ms,
    t.error,
    t.scheduled_at,
    t.worker_pid,
    t.payload,
    cr.queue,
    cr.description AS command_description
FROM worker.tasks AS t
JOIN worker.command_registry AS cr ON cr.command = t.command;

GRANT SELECT ON public.worker_task TO authenticated, admin_user, regular_user;

-- Drop info column
ALTER TABLE worker.tasks DROP COLUMN info;

END;
