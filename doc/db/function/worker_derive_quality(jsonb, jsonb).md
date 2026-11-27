```sql
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_hash_partition_size integer := GREATEST(1, 16384 / public.get_partition_count_target());
    -- A full run: one range per analytics worker, so each does one large pass (fewer tasks than the
    -- small partitions, which cost a task's start and commit each).
    v_full_partition_size integer := 16384 / GREATEST(1, (SELECT q.default_concurrency FROM worker.queue_registry AS q WHERE q.queue = 'analytics'));
    v_full boolean;
    v_hash_partition int4range;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    -- Every partition on a full recalculation (valid_from -infinity and valid_until infinity, see
    -- worker.enqueue_derive_statistical_unit_all; a full statistical_unit refresh empties
    -- quality_finding). Otherwise the partitions holding a changed unit: the cycle's changed units'
    -- hash slots, recorded by worker.derive_statistical_unit and cleared by
    -- worker.statistical_history_facet_delta_reduce after this step.
    v_full := v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date;

    FOR v_hash_partition IN
        SELECT int4range(p.start, LEAST(p.start + v_full_partition_size, 16384))
        FROM generate_series(0, 16383, v_full_partition_size) AS p(start)
        WHERE v_full
        UNION
        SELECT int4range((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size,
                         LEAST((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384))
        FROM public.statistical_unit_facet_dirty_hash_slots AS d
        WHERE NOT v_full
        ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_quality_partition',
            p_payload => jsonb_build_object('command', 'derive_quality_partition', 'hash_partition', v_hash_partition::text),
            p_parent_id => v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'full', v_full);
END;
$procedure$
```
