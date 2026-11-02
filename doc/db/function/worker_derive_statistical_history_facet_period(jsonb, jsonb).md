```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_record_changes boolean := COALESCE((payload->>'record_changes')::boolean, false);
    v_row_count bigint;
BEGIN
    -- The slice as it was, so the combinations this rewrite changes, including
    -- the removed ones, can be recorded for the scoped reduce.
    IF v_record_changes THEN
        IF to_regclass('pg_temp._history_facet_slice_before') IS NOT NULL THEN DROP TABLE _history_facet_slice_before; END IF;
        CREATE TEMP TABLE _history_facet_slice_before ON COMMIT DROP AS
        SELECT * FROM public.statistical_history_facet_partitions
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_slot >= lower(v_hash_partition)
           AND hash_slot <  upper(v_hash_partition);
    END IF;

    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- A combination changed when any of its rows in the slice was added,
    -- altered or removed: the symmetric difference of before and after.
    -- Inserted in key order, so concurrent children wait on each other's
    -- uncommitted keys in the same order and cannot deadlock.
    IF v_record_changes THEN
        INSERT INTO worker.statistical_history_facet_changed
        SELECT DISTINCT d.resolution, d.year, d.month, d.unit_type,
               d.primary_activity_category_path, d.secondary_activity_category_path,
               d.sector_path, d.legal_form_id, d.physical_region_path,
               d.physical_country_id, d.unit_size_id, d.status_id
        FROM (
            (SELECT * FROM _history_facet_slice_before
             EXCEPT ALL
             SELECT * FROM public.statistical_history_facet_partitions
              WHERE resolution = v_resolution
                AND year = v_year
                AND month IS NOT DISTINCT FROM v_month
                AND hash_slot >= lower(v_hash_partition)
                AND hash_slot <  upper(v_hash_partition))
            UNION ALL
            (SELECT * FROM public.statistical_history_facet_partitions
              WHERE resolution = v_resolution
                AND year = v_year
                AND month IS NOT DISTINCT FROM v_month
                AND hash_slot >= lower(v_hash_partition)
                AND hash_slot <  upper(v_hash_partition)
             EXCEPT ALL
             SELECT * FROM _history_facet_slice_before)
        ) AS d
        ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
        ON CONFLICT DO NOTHING;
    END IF;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```
