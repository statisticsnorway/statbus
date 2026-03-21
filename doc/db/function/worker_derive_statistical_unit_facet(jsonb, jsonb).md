```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    -- Range-based spawning variables
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: get all populated partitions
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        );
    ELSE
        -- Partial refresh: use dirty partitions
        v_partitions_to_process := v_dirty_partitions;
    END IF;

    -- Adaptive range-based spawning: group adjacent slots into ranges.
    -- Target 4-64 children based on how many slots need processing.
    v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
    v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

    FOR v_range_start IN 0..255 BY v_range_size LOOP
        v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
        -- Only spawn if there are partitions in this range
        IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq_from', v_range_start,
                    'partition_seq_to', v_range_end
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % range children (range_size=%)',
        v_child_count, v_range_size;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
```
