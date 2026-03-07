```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_dirty_partitions INT[];
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Extract dirty partitions from payload (NULL = full refresh)
    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_unit_facet;

    -- Aggregate from UNLOGGED staging table into main table
    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;

    -- Clear only the dirty partitions that were processed
    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
        RAISE DEBUG 'statistical_unit_facet_reduce: cleared % dirty partitions', array_length(v_dirty_partitions, 1);
    ELSE
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
        RAISE DEBUG 'statistical_unit_facet_reduce: full refresh -- truncated dirty partitions';
    END IF;

    -- Enqueue next phase: derive_statistical_history_facet
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$procedure$
```
