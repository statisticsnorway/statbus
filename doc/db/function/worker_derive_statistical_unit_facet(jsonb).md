```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_i INT;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- =====================================================================
    -- INTEGRITY CHECK: Ensure partition table is fully populated.
    -- UNLOGGED table loses data on crash; also handles first-run case.
    -- If partition table is incomplete, force a full refresh.
    -- =====================================================================
    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    -- Snapshot dirty partitions (atomically read current state)
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        -- Partition table lost data (crash or first run) -> force full refresh
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    -- Enqueue reduce task with the snapshot of dirty partitions in payload.
    -- This way reduce knows exactly which partitions to clear from dirty tracking.
    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_dirty_partitions => v_dirty_partitions,
        p_round_priority_base := v_round_priority_base
    );

    -- Spawn partition children
    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: only partitions that have data
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh -- spawning % partition children (populated)',
            v_expected_partitions;
        FOR v_i IN
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id,
                p_priority := v_round_priority_base
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: only dirty partitions
        RAISE DEBUG 'derive_statistical_unit_facet: Partial refresh -- spawning % dirty partition children',
            array_length(v_dirty_partitions, 1);
        FOREACH v_i IN ARRAY v_dirty_partitions LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id,
                p_priority := v_round_priority_base
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % partition children', v_child_count;
END;
$procedure$
```
