```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
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
    v_task_id BIGINT;
BEGIN
    -- Still need task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY process_start_at DESC NULLS LAST, id DESC
    LIMIT 1;

    -- Capture function return into p_info (was PERFORM, now SELECT INTO)
    SELECT worker.derive_statistical_unit(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges,
        p_power_group_id_ranges => v_power_group_id_ranges,
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_task_id => v_task_id
    ) INTO p_info;
END;
$procedure$
```
