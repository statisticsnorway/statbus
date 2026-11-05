```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_delta(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_task_id bigint;
    v_state worker.statistical_history_facet_delta_state;
    v_rebuild boolean;
    v_range_size integer;
    v_range int4range;
    v_child_count integer := 0;
    v_discarded bigint := 0;
BEGIN
    SELECT id INTO v_task_id FROM worker.tasks
     WHERE state = 'processing' AND worker_pid = pg_backend_pid()
     ORDER BY id DESC LIMIT 1;
    SELECT * INTO v_state FROM worker.statistical_history_facet_delta_state FOR UPDATE;

    -- Rebuild on an all-time derive (valid_from = -infinity, valid_until = infinity:
    -- worker.enqueue_derive_statistical_unit_all), while an earlier rebuild is not yet added, when units
    -- were flushed without their deltas, and on a cycle that finds the tables empty while statistical_unit
    -- has rows.
    v_rebuild := ((payload->>'valid_from')::date = '-infinity'::date AND (payload->>'valid_until')::date = 'infinity'::date)
        OR v_state.rebuild_generation IS NOT NULL
        OR v_state.rebuild_needed
        OR (NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_delta LIMIT 1)
            AND EXISTS (SELECT 1 FROM public.statistical_unit LIMIT 1));

    IF v_rebuild THEN
        -- The rebuild's rows replace the tables, so no earlier staged row is needed.
        SELECT count(*) INTO v_discarded FROM public.statistical_history_facet_delta_staging;
        TRUNCATE public.statistical_history_facet_delta_staging;
        UPDATE worker.statistical_history_facet_delta_state
           SET rebuild_generation = v_task_id, rebuild_needed = false;
    ELSE
        -- Rows of a cycle whose flush never committed: its units are still in statistical_unit_staging
        -- and are staged again below, against the same statistical_unit.
        WITH s AS (DELETE FROM public.statistical_history_facet_delta_staging
                    WHERE generation > v_state.flushed_generation RETURNING 1)
        SELECT count(*) INTO v_discarded FROM s;
    END IF;

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
            p_command => 'derive_statistical_history_facet_delta_partition',
            p_payload => jsonb_build_object('command', 'derive_statistical_history_facet_delta_partition',
                                            'hash_range', v_range::text, 'rebuild', v_rebuild,
                                            'generation', v_task_id),
            p_parent_id => v_task_id);
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'rebuild', v_rebuild, 'range_size', v_range_size,
                                 'unflushed_rows_discarded', v_discarded);
END;
$procedure$
```
