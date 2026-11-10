```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_staging_count bigint;
    v_history_task worker.tasks;
BEGIN
    -- Clean up obsolete years
    DELETE FROM public.timesegments_years AS ty
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments AS t
        WHERE t.valid_from >= make_date(ty.year, 1, 1)
          AND t.valid_from < make_date(ty.year + 1, 1, 1)
        LIMIT 1
    );

    -- Auto-tune partition count target based on current data size
    CALL admin.adjust_partition_count_target();

    SELECT h.* INTO v_history_task
      FROM worker.tasks AS me
      JOIN worker.tasks AS h ON h.parent_id = me.parent_id AND h.command = 'derive_statistical_history_facet_delta'
     WHERE me.state = 'processing' AND me.worker_pid = pg_backend_pid() AND me.command = 'statistical_unit_flush_staging'
     ORDER BY h.id DESC LIMIT 1;
    IF v_history_task.state = 'completed' THEN
        UPDATE worker.statistical_history_facet_delta_state SET flushed_generation = v_history_task.id
         WHERE true; -- the single state row (unique index on (true))
    ELSIF EXISTS (SELECT 1 FROM public.statistical_unit_staging) THEN
        UPDATE worker.statistical_history_facet_delta_state SET rebuild_needed = true
         WHERE NOT rebuild_needed;
    END IF;

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count,
                                 'history_generation_flushed', CASE WHEN v_history_task.state = 'completed' THEN v_history_task.id END);
END;
$procedure$
```
