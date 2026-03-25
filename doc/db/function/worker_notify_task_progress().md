```sql
CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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

    -- Also check: is there a QUEUED pipeline behind the current one?
    -- A pending collect_changes means new changes are waiting to be processed.
    -- Show units as pending so the UI indicates queued work.
    IF NOT v_units_active AND EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command = 'collect_changes' AND state = 'pending'
          AND id <> v_pipeline_id
    ) THEN
        v_units_active := true;
        v_units_step := 'collect_changes';
    END IF;

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
        -- Step: the depth-2 child of the phase root that's active.
        -- This matches pipeline_step_weight entries for weighted progress.
        IF v_pipeline_state IN ('pending', 'processing') THEN
            v_units_step := 'collect_changes';
        ELSE
            SELECT t.command INTO v_units_step
            FROM worker.tasks AS t
            WHERE t.parent_id = v_units_phase_id
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1;
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
            -- Step: the depth-2 child of the phase root that's active.
            -- This matches pipeline_step_weight entries for weighted progress.
            SELECT t.command INTO v_reports_step
            FROM worker.tasks AS t
            WHERE t.parent_id = v_reports_phase_id
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1;

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

    -- Only send idle signals when the phase is truly idle (not active AND not pending).
    -- A pending phase is queued work — not idle.
    IF NOT v_units_active THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
    IF NOT v_reports_active
       AND (v_reports_phase_state IS NULL OR v_reports_phase_state IN ('completed', 'failed')) THEN
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    END IF;
END;
$function$
```
