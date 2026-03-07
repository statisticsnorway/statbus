```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        -- Delete and reinsert for this partition × period in the UNLOGGED partition table
        DELETE FROM public.statistical_history_facet_partitions
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history_facet_partitions (
            partition_seq,
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary
        )
        SELECT v_partition_seq, h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
    ELSE
        -- Legacy non-partitioned path: write directly to main table
        DELETE FROM public.statistical_history_facet
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history_facet
        SELECT h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month) AS h;
    END IF;

    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;
END;
$procedure$
```
