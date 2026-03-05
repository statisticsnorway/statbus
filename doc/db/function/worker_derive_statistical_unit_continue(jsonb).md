```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_continue(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_batch_offset int = COALESCE((payload->>'batch_offset')::int, 0);
    v_task_id BIGINT;
BEGIN
    -- Get current task ID from the tasks table (the one being processed)
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;
    
    -- Call the impl function with the batch_offset from payload
    PERFORM worker.derive_statistical_unit_impl(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_batch_offset := v_batch_offset
    );
END;
$procedure$
```
