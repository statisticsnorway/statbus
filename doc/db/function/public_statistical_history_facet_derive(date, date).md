```sql
CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Clear target rows for the requested temporal scope.
    DELETE FROM public.statistical_history_facet AS shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    WHERE shf.resolution = tp.resolution
      AND shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month;

    -- Bulk INSERT with cross-slot aggregation. The def function returns
    -- per-slot rows (RETURNS SETOF statistical_history_facet_partitions);
    -- target is keyed by (resolution, year, month, dims_8). GROUP BY the
    -- target's natural key and SUM/jsonb_stats_merge_agg across slots.
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count, physical_country_change_count,
        physical_address_change_count, unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        f.resolution, f.year, f.month, f.unit_type,
        f.primary_activity_category_path, f.secondary_activity_category_path,
        f.sector_path, f.legal_form_id, f.physical_region_path,
        f.physical_country_id, f.unit_size_id, f.status_id,
        SUM(f.exists_count)::integer,
        SUM(f.exists_change)::integer,
        SUM(f.exists_added_count)::integer,
        SUM(f.exists_removed_count)::integer,
        SUM(f.countable_count)::integer,
        SUM(f.countable_change)::integer,
        SUM(f.countable_added_count)::integer,
        SUM(f.countable_removed_count)::integer,
        SUM(f.births)::integer,
        SUM(f.deaths)::integer,
        SUM(f.name_change_count)::integer,
        SUM(f.primary_activity_category_change_count)::integer,
        SUM(f.secondary_activity_category_change_count)::integer,
        SUM(f.sector_change_count)::integer,
        SUM(f.legal_form_change_count)::integer,
        SUM(f.physical_region_change_count)::integer,
        SUM(f.physical_country_change_count)::integer,
        SUM(f.physical_address_change_count)::integer,
        SUM(f.unit_size_change_count)::integer,
        SUM(f.status_change_count)::integer,
        public.jsonb_stats_merge_agg(f.stats_summary)
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) AS tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) AS f
    GROUP BY f.resolution, f.year, f.month, f.unit_type,
             f.primary_activity_category_path, f.secondary_activity_category_path,
             f.sector_path, f.legal_form_id, f.physical_region_path,
             f.physical_country_id, f.unit_size_id, f.status_id;
END;
$function$
```
