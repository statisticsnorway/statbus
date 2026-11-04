```sql
CREATE OR REPLACE PROCEDURE worker.derive_history_delta(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_task_id bigint;
    v_rebuild boolean;
    v_range_size integer;
    v_range int4range;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id FROM worker.tasks
     WHERE state = 'processing' AND worker_pid = pg_backend_pid()
     ORDER BY id DESC LIMIT 1;

    -- An all-time derive (valid_from = -infinity, valid_until = infinity: worker.enqueue_derive_statistical_unit_all)
    -- rebuilds, and so does a first cycle that finds the tables empty while statistical_unit has rows.
    v_rebuild := ((payload->>'valid_from')::date = '-infinity'::date AND (payload->>'valid_until')::date = 'infinity'::date)
        OR (NOT EXISTS (SELECT 1 FROM public.history_stock_delta LIMIT 1)
            AND EXISTS (SELECT 1 FROM public.statistical_unit LIMIT 1));

    v_range_size := GREATEST(1, 16384 / public.partition_count_target_for(GREATEST(
        (SELECT count(*) FROM public.statistical_unit),
        (SELECT count(*) FROM public.statistical_unit_staging))));

    FOR v_range IN
        SELECT DISTINCT int4range((s.hash_slot / v_range_size) * v_range_size,
                                  LEAST((s.hash_slot / v_range_size) * v_range_size + v_range_size, 16384))
          FROM (SELECT hash_slot FROM public.statistical_unit_staging
                UNION ALL
                SELECT hash_slot FROM public.statistical_unit WHERE v_rebuild) AS s
         ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_history_delta_range',
            p_payload => jsonb_build_object('command', 'derive_history_delta_range',
                                            'hash_range', v_range::text, 'rebuild', v_rebuild),
            p_parent_id => v_task_id);
        v_child_count := v_child_count + 1;
    END LOOP;

    -- A rebuild starts from empty tables and an empty staging (rows staged by a cycle that never
    -- reached its reduce are covered by the rebuild).
    IF v_rebuild THEN
        TRUNCATE public.history_stock_delta, public.history_flow_delta,
                 public.history_stock_delta_staging, public.history_flow_delta_staging;
    END IF;
    p_info := jsonb_build_object('child_count', v_child_count, 'rebuild', v_rebuild, 'range_size', v_range_size);
END;
$procedure$
```
