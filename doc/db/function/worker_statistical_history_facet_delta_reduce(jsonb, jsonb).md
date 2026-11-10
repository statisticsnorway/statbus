```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_state worker.statistical_history_facet_delta_state;
    v_staged bigint;
    v_applied text;
BEGIN
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;
    SELECT count(*) INTO v_staged FROM public.statistical_history_facet_delta_staging
     WHERE generation <= v_state.flushed_generation;
    IF v_state.rebuild_generation IS NULL THEN
        CALL worker.statistical_history_facet_delta_apply();
        v_applied := 'added';
    ELSIF v_state.rebuild_generation <= v_state.flushed_generation THEN
        CALL worker.statistical_history_facet_delta_apply(p_replace => true);
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_generation = NULL
         WHERE rebuild_generation IS NOT NULL;
        v_applied := 'replaced';
    ELSE
        -- The rebuild cycle's flush has not committed: the tables keep their rows, and the next cycle
        -- rebuilds again.
        v_applied := 'rebuild not flushed';
    END IF;
    CALL public.statistical_history_period_refresh();
    TRUNCATE public.statistical_unit_facet_dirty_hash_slots;
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);
    p_info := jsonb_build_object('rows_staged', v_staged, 'applied', v_applied);
END;
$procedure$
```
