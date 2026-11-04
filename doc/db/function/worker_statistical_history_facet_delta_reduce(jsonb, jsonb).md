```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_stock_staged bigint;
    v_flow_staged bigint;
BEGIN
    SELECT count(*) INTO v_stock_staged FROM public.statistical_history_facet_stock_delta_staging;
    SELECT count(*) INTO v_flow_staged FROM public.statistical_history_facet_flow_delta_staging;
    CALL worker.statistical_history_facet_delta_apply();
    CALL public.statistical_history_period_refresh();
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    p_info := jsonb_build_object('stock_rows_staged', v_stock_staged, 'flow_rows_staged', v_flow_staged);
END;
$procedure$
```
