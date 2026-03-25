```sql
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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

    -- Also check for a queued pipeline behind the current one
    IF NOT v_active AND EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command = 'collect_changes' AND state = 'pending'
          AND id <> v_pipeline_id
    ) THEN
        v_active := true;
        v_step := 'collect_changes';
        RETURN jsonb_build_object(
            'active', true,
            'pending', true,
            'step', 'collect_changes'
        );
    END IF;

    IF NOT v_active THEN
        RETURN jsonb_build_object('active', false);
    END IF;

    -- Step
    IF v_pipeline_state IN ('pending', 'processing') THEN
        v_step := 'collect_changes';
    ELSE
        SELECT t.command INTO v_step
        FROM worker.tasks AS t
        WHERE t.parent_id = v_units_phase_id
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;
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
$function$
```
