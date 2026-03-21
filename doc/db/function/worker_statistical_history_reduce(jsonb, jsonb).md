```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        partition_seq
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary),
        NULL
    FROM public.statistical_history
    WHERE partition_seq IS NOT NULL
    GROUP BY resolution, year, month, unit_type;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object('rows_reduced', v_row_count);
END;
$procedure$
```
