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
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
    v_ranges int4multirange;
    v_left_keys bigint := 0;
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
    -- worker.enqueue_derive_statistical_unit_all), or when the staging cache
    -- is empty (fresh install, unclean shutdown of the UNLOGGED table). A
    -- full rebuild drops the whole cache first: slots whose units no longer
    -- exist are never dirty and would otherwise keep counting in the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_unit_facet_staging WHERE true; -- every row: a full-range derive rebuilds all staging
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    IF v_dirty_hash_slots IS NOT NULL THEN
        -- The ranges the children rewrite, and the facet keys staged there before they do: the
        -- facets the units may leave (worker.statistical_unit_facet_state, recount_keys).
        SELECT range_agg(int4range(r.range_from, LEAST(r.range_from + v_hash_partition_size, 16384)))
          INTO v_ranges
          FROM (SELECT DISTINCT (d.slot / v_hash_partition_size) * v_hash_partition_size AS range_from
                  FROM unnest(v_dirty_hash_slots) AS d(slot)) AS r;
        INSERT INTO worker.statistical_unit_facet_recount_keys
        SELECT DISTINCT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
          FROM public.statistical_unit_facet_staging AS s
          JOIN unnest(v_ranges) AS r(hash_range)
            ON lower(r.hash_range) <= s.hash_slot AND s.hash_slot < upper(r.hash_range);
        GET DIAGNOSTICS v_left_keys := ROW_COUNT;
        UPDATE worker.statistical_unit_facet_state
           SET recount_ranges = recount_ranges + v_ranges
         WHERE NOT recount_all;

        -- One child per partition range holding a dirty slot, the same ranges
        -- as the full rebuild (STATBUS-543).
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (d.slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM unnest(v_dirty_hash_slots) AS d(slot)
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- All staging is rewritten, so every facet is recounted.
        UPDATE worker.statistical_unit_facet_state
           SET recount_all = true, recount_ranges = '{}'
         WHERE NOT recount_all OR recount_ranges <> '{}';
        DELETE FROM worker.statistical_unit_facet_recount_keys WHERE true; -- every row: every facet is recounted
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count, 'left_keys', v_left_keys);
END;
$procedure$
```
