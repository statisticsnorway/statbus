-- Migration 20260324203631: fix_notify_progress_collect_changes_state
--
-- Redesign: Pipeline progress based on tree structure, not command enumeration.
--
-- Principle: The structured concurrency tree encodes phase membership.
-- Phase activity is determined by the phase root's state, not by scanning
-- for specific child commands. Progress is counted from the deepest active
-- concurrent parent's children.
--
-- Only three structural names are needed:
--   collect_changes, derive_units_phase, derive_reports_phase
-- Everything else is derived from parent_id relationships.
BEGIN;

CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $notify_task_progress$
DECLARE
    v_payload JSONB;
    v_phases JSONB := '[]'::jsonb;
    -- Pipeline root
    v_pipeline_id BIGINT;
    v_pipeline_state worker.task_state;
    -- Phase roots
    v_units_phase_id BIGINT;
    v_units_phase_state worker.task_state;
    v_reports_phase_id BIGINT;
    v_reports_phase_state worker.task_state;
    -- Phase 1
    v_units_active BOOLEAN;
    v_units_step TEXT;
    v_units_total BIGINT;
    v_units_completed BIGINT;
    -- Phase 2
    v_reports_active BOOLEAN;
    v_reports_step TEXT;
    v_reports_total BIGINT;
    v_reports_completed BIGINT;
    -- Shared
    v_concurrent_parent_id BIGINT;
    v_effective_info JSONB;
BEGIN
    -- 1. Find the active pipeline root.
    -- Prefer processing/waiting (actively running) over pending (queued).
    -- Without this, a second queued collect_changes would shadow the running one.
    SELECT id, state INTO v_pipeline_id, v_pipeline_state
    FROM worker.tasks
    WHERE command = 'collect_changes'
      AND state NOT IN ('completed', 'failed')
    ORDER BY
      CASE WHEN state IN ('processing', 'waiting') THEN 0 ELSE 1 END,
      id DESC
    LIMIT 1;

    IF v_pipeline_id IS NULL THEN
        -- No active pipeline. Send idle for both phases.
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
        RETURN;
    END IF;

    -- 2. Find phase roots (direct children of pipeline root)
    SELECT id, state INTO v_units_phase_id, v_units_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_units_phase';

    SELECT id, state INTO v_reports_phase_id, v_reports_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_reports_phase';

    -- 3. Phase activity from root states
    -- Units: active when pipeline is collecting (pending/processing)
    --        OR units phase root is not yet terminal
    v_units_active := v_pipeline_state IN ('pending', 'processing')
        OR (v_units_phase_state IS NOT NULL
            AND v_units_phase_state NOT IN ('completed', 'failed'));

    -- Reports: active when reports phase root is processing/waiting,
    -- OR when reports is pending but units is already done (bridges the gap
    -- between derive_units_phase completing and derive_reports_phase starting).
    v_reports_active := v_reports_phase_state IN ('processing', 'waiting')
        OR (v_reports_phase_state = 'pending'
            AND v_units_phase_state IN ('completed', 'failed'));

    -- 4. Effective counts: from the depth-2 child that has them (persists after completion)
    IF v_units_phase_id IS NOT NULL THEN
        SELECT t.info INTO v_effective_info
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.info ? 'effective_legal_unit_count'
        ORDER BY t.id LIMIT 1;
    END IF;

    -- 5. Phase 1 details
    IF v_units_active THEN
        -- Step: deepest processing/waiting task in the phase subtree (max 3 levels)
        IF v_pipeline_state IN ('pending', 'processing') THEN
            v_units_step := 'collect_changes';
        ELSE
            SELECT t.command INTO v_units_step
            FROM worker.tasks AS t
            WHERE t.state IN ('processing', 'waiting')
              AND (t.id = v_units_phase_id
                   OR t.parent_id = v_units_phase_id
                   OR EXISTS (SELECT 1 FROM worker.tasks AS p
                              WHERE p.id = t.parent_id AND p.parent_id = v_units_phase_id))
            ORDER BY t.depth DESC, t.id DESC LIMIT 1;
        END IF;

        -- Progress: children of the deepest active concurrent parent in the phase
        SELECT t.id INTO v_concurrent_parent_id
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.child_mode = 'concurrent'
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.depth DESC LIMIT 1;

        IF v_concurrent_parent_id IS NOT NULL THEN
            SELECT count(*),
                   count(*) FILTER (WHERE state IN ('completed', 'failed'))
            INTO v_units_total, v_units_completed
            FROM worker.tasks
            WHERE parent_id = v_concurrent_parent_id;
        ELSE
            v_units_total := 0;
            v_units_completed := 0;
        END IF;

        v_phases := v_phases || jsonb_build_array(jsonb_build_object(
            'phase', 'is_deriving_statistical_units',
            'active', v_units_active,
            'pending', false,
            'step', v_units_step,
            'total', COALESCE(v_units_total, 0),
            'completed', COALESCE(v_units_completed, 0),
            'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
            'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
            'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
            'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
        ));
    END IF;

    -- 6. Phase 2 details
    -- Always include reports when the phase exists (even when pending),
    -- so the UI can show "pending" with effective counts.
    IF v_reports_phase_id IS NOT NULL AND v_reports_phase_state NOT IN ('completed', 'failed') THEN
        IF v_reports_active THEN
            -- Step: deepest processing/waiting task in the reports subtree (max 3 levels)
            SELECT t.command INTO v_reports_step
            FROM worker.tasks AS t
            WHERE t.state IN ('processing', 'waiting')
              AND (t.id = v_reports_phase_id
                   OR t.parent_id = v_reports_phase_id
                   OR EXISTS (SELECT 1 FROM worker.tasks AS p
                              WHERE p.id = t.parent_id AND p.parent_id = v_reports_phase_id))
            ORDER BY t.depth DESC, t.id DESC LIMIT 1;

            -- Progress: children of the deepest active concurrent parent in the phase
            SELECT t.id INTO v_concurrent_parent_id
            FROM worker.tasks AS t
            WHERE t.parent_id = v_reports_phase_id
              AND t.child_mode = 'concurrent'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.depth DESC LIMIT 1;

            IF v_concurrent_parent_id IS NOT NULL THEN
                SELECT count(*),
                       count(*) FILTER (WHERE state IN ('completed', 'failed'))
                INTO v_reports_total, v_reports_completed
                FROM worker.tasks
                WHERE parent_id = v_concurrent_parent_id;
            END IF;
        END IF;

        v_phases := v_phases || jsonb_build_array(jsonb_build_object(
            'phase', 'is_deriving_reports',
            'active', v_reports_active,
            'pending', v_reports_phase_state = 'pending',
            'step', v_reports_step,
            'total', COALESCE(v_reports_total, 0),
            'completed', COALESCE(v_reports_completed, 0),
            'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
            'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
            'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
            'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
        ));
    END IF;

    -- 7. Send progress and idle signals
    IF jsonb_array_length(v_phases) > 0 THEN
        v_payload := jsonb_build_object('type', 'pipeline_progress', 'phases', v_phases);
        PERFORM pg_notify('worker_status', v_payload::text);
    END IF;

    IF NOT v_units_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
    IF NOT v_reports_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    END IF;
END;
$notify_task_progress$;

-- Update RPC functions to use the same principled logic
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $is_deriving_statistical_units$
DECLARE
    v_pipeline_id BIGINT;
    v_pipeline_state worker.task_state;
    v_units_phase_id BIGINT;
    v_units_phase_state worker.task_state;
    v_active BOOLEAN;
    v_step TEXT;
    v_total BIGINT;
    v_completed BIGINT;
    v_concurrent_parent_id BIGINT;
    v_effective_info JSONB;
BEGIN
    SELECT id, state INTO v_pipeline_id, v_pipeline_state
    FROM worker.tasks
    WHERE command = 'collect_changes' AND state NOT IN ('completed', 'failed')
    ORDER BY
      CASE WHEN state IN ('processing', 'waiting') THEN 0 ELSE 1 END,
      id DESC
    LIMIT 1;

    IF v_pipeline_id IS NULL THEN
        RETURN jsonb_build_object('active', false);
    END IF;

    SELECT id, state INTO v_units_phase_id, v_units_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_units_phase';

    v_active := v_pipeline_state IN ('pending', 'processing')
        OR (v_units_phase_state IS NOT NULL
            AND v_units_phase_state NOT IN ('completed', 'failed'));

    IF NOT v_active THEN
        RETURN jsonb_build_object('active', false);
    END IF;

    -- Step
    IF v_pipeline_state IN ('pending', 'processing') THEN
        v_step := 'collect_changes';
    ELSE
        SELECT t.command INTO v_step
        FROM worker.tasks AS t
        WHERE t.state IN ('processing', 'waiting')
          AND (t.id = v_units_phase_id
               OR t.parent_id = v_units_phase_id
               OR EXISTS (SELECT 1 FROM worker.tasks AS p
                          WHERE p.id = t.parent_id AND p.parent_id = v_units_phase_id))
        ORDER BY t.depth DESC, t.id DESC LIMIT 1;
    END IF;

    -- Progress
    SELECT t.id INTO v_concurrent_parent_id
    FROM worker.tasks AS t
    WHERE t.parent_id = v_units_phase_id
      AND t.child_mode = 'concurrent'
      AND t.state IN ('processing', 'waiting')
    ORDER BY t.depth DESC LIMIT 1;

    IF v_concurrent_parent_id IS NOT NULL THEN
        SELECT count(*), count(*) FILTER (WHERE state IN ('completed', 'failed'))
        INTO v_total, v_completed
        FROM worker.tasks WHERE parent_id = v_concurrent_parent_id;
    END IF;

    -- Effective counts
    SELECT t.info INTO v_effective_info
    FROM worker.tasks AS t
    WHERE t.parent_id = v_units_phase_id
      AND t.info ? 'effective_legal_unit_count'
    ORDER BY t.id LIMIT 1;

    RETURN jsonb_build_object(
        'active', true,
        'step', v_step,
        'total', COALESCE(v_total, 0),
        'completed', COALESCE(v_completed, 0),
        'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
        'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
        'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
        'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
    );
END;
$is_deriving_statistical_units$;

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $is_deriving_reports$
DECLARE
    v_pipeline_id BIGINT;
    v_units_phase_id BIGINT;
    v_units_phase_state worker.task_state;
    v_reports_phase_id BIGINT;
    v_reports_phase_state worker.task_state;
    v_active BOOLEAN;
    v_step TEXT;
    v_total BIGINT;
    v_completed BIGINT;
    v_concurrent_parent_id BIGINT;
    v_effective_info JSONB;
BEGIN
    SELECT id INTO v_pipeline_id
    FROM worker.tasks
    WHERE command = 'collect_changes' AND state NOT IN ('completed', 'failed')
    ORDER BY
      CASE WHEN state IN ('processing', 'waiting') THEN 0 ELSE 1 END,
      id DESC
    LIMIT 1;

    IF v_pipeline_id IS NULL THEN
        RETURN jsonb_build_object('active', false);
    END IF;

    SELECT id, state INTO v_units_phase_id, v_units_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_units_phase';

    SELECT id, state INTO v_reports_phase_id, v_reports_phase_state
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_reports_phase';

    -- Active when processing/waiting, or pending but units already done (gap bridge)
    v_active := v_reports_phase_state IN ('processing', 'waiting')
        OR (v_reports_phase_state = 'pending'
            AND v_units_phase_state IN ('completed', 'failed'));

    IF NOT COALESCE(v_active, false) THEN
        RETURN jsonb_build_object('active', false);
    END IF;

    -- Step
    SELECT t.command INTO v_step
    FROM worker.tasks AS t
    WHERE t.state IN ('processing', 'waiting')
      AND (t.id = v_reports_phase_id
           OR t.parent_id = v_reports_phase_id
           OR EXISTS (SELECT 1 FROM worker.tasks AS p
                      WHERE p.id = t.parent_id AND p.parent_id = v_reports_phase_id))
    ORDER BY t.depth DESC, t.id DESC LIMIT 1;

    -- Progress
    SELECT t.id INTO v_concurrent_parent_id
    FROM worker.tasks AS t
    WHERE t.parent_id = v_reports_phase_id
      AND t.child_mode = 'concurrent'
      AND t.state IN ('processing', 'waiting')
    ORDER BY t.depth DESC LIMIT 1;

    IF v_concurrent_parent_id IS NOT NULL THEN
        SELECT count(*), count(*) FILTER (WHERE state IN ('completed', 'failed'))
        INTO v_total, v_completed
        FROM worker.tasks WHERE parent_id = v_concurrent_parent_id;
    END IF;

    -- Effective counts from units phase (persisted in info after completion)
    SELECT id INTO v_units_phase_id
    FROM worker.tasks
    WHERE parent_id = v_pipeline_id AND command = 'derive_units_phase';

    IF v_units_phase_id IS NOT NULL THEN
        SELECT t.info INTO v_effective_info
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.info ? 'effective_legal_unit_count'
        ORDER BY t.id LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'active', true,
        'step', v_step,
        'total', COALESCE(v_total, 0),
        'completed', COALESCE(v_completed, 0),
        'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
        'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
        'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
        'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
    );
END;
$is_deriving_reports$;

END;
