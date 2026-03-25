```sql
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
        -- If pending (not active, but queued), return pending with counts
        IF v_reports_phase_state = 'pending' THEN
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
                'active', false,
                'pending', true,
                'effective_establishment_count', (v_effective_info->>'effective_establishment_count')::int,
                'effective_legal_unit_count', (v_effective_info->>'effective_legal_unit_count')::int,
                'effective_enterprise_count', (v_effective_info->>'effective_enterprise_count')::int,
                'effective_power_group_count', (v_effective_info->>'effective_power_group_count')::int
            );
        END IF;
        RETURN jsonb_build_object('active', false);
    END IF;

    -- Step
    SELECT t.command INTO v_step
    FROM worker.tasks AS t
    WHERE t.parent_id = v_reports_phase_id
      AND t.state IN ('processing', 'waiting')
    ORDER BY t.id DESC LIMIT 1;

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
$function$
```
