```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    -- Range-based spawning
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

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history: No partition entries exist, forcing full refresh';
    END IF;

    IF v_dirty_partitions IS NULL THEN
        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            ORDER BY report_partition_seq
        );
    ELSE
        v_partitions_to_process := v_dirty_partitions;
    END IF;

    -- Adaptive range-based spawning
    v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
    v_range_size := GREATEST(1, ceil(256.0 / v_target_children));

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        FOR v_range_start IN 0..255 BY v_range_size LOOP
            v_range_end := LEAST(v_range_start + v_range_size - 1, 255);
            IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_range_start,
                        'partition_seq_to', v_range_end
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period x range children',
        v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
```
