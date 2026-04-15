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
    v_modulus INT;
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    v_modulus := public.get_report_partition_modulus();

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NOT NULL THEN
            FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_dirty_partitions[i],
                        'partition_seq_to', v_dirty_partitions[i]
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            IF v_partitions_to_process IS NULL THEN
                v_partitions_to_process := ARRAY(
                    SELECT DISTINCT report_partition_seq
                    FROM public.statistical_unit
                    ORDER BY report_partition_seq
                );
                v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
                v_range_size := GREATEST(1, ceil(v_modulus::numeric / v_target_children));
            END IF;

            FOR v_range_start IN 0..(v_modulus - 1) BY v_range_size LOOP
                v_range_end := LEAST(v_range_start + v_range_size - 1, v_modulus - 1);
                IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                    PERFORM worker.spawn(
                        p_command => 'derive_statistical_history_period',
                        p_payload => jsonb_build_object(
                            'command', 'derive_statistical_history_period',
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
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
```
