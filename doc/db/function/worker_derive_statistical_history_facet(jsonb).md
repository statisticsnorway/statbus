```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Read dirty partitions
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet (UNLOGGED data lost or first run), force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history_facet: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task
    PERFORM worker.enqueue_statistical_history_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    -- Spawn period x partition children
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            -- Include all partitions (not just used_for_counting) because
            -- statistical_history_facet tracks exists_count for all units
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period x partition children', v_child_count;
END;
$procedure$
```
