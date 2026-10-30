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
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when no per-slot rows
    -- exist yet (fresh install). A full rebuild drops every per-slot row
    -- first, so slots and periods without units do not survive the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_history WHERE hash_partition IS NOT NULL;
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE hash_partition IS NOT NULL LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_hash_slots IS NOT NULL THEN
            -- Dirty branch: one child per partition range (16384 /
            -- partition_count_target slots, the same ranges as the full
            -- rebuild) that holds a dirty slot. The child rebuilds every slot
            -- of its range, so task count is bounded by the partition setting,
            -- not by the number of changed slots (STATBUS-543).
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (d.slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM unnest(v_dirty_hash_slots) AS d(slot)
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            -- Full-rebuild branch: data-driven DISTINCT ranges, derived from
            -- the actual set of slots occupied in statistical_unit.
            FOR v_hash_partition IN
                SELECT DISTINCT int4range(
                    (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                    LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
                )
                FROM public.statistical_unit AS su
                ORDER BY 1
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'hash_partition', v_hash_partition::text
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$procedure$
```
