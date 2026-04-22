```sql
CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month
      AND shf.resolution = tp.resolution;

    -- Bulk INSERT using LATERAL join — explicit column list excludes hash_slot.
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
        f.exists_count, f.exists_change, f.exists_added_count, f.exists_removed_count,
        f.countable_count, f.countable_change, f.countable_added_count, f.countable_removed_count,
        f.births, f.deaths,
        f.name_change_count, f.primary_activity_category_change_count,
        f.secondary_activity_category_change_count, f.sector_change_count,
        f.legal_form_change_count, f.physical_region_change_count, f.physical_country_change_count,
        f.physical_address_change_count, f.unit_size_change_count, f.status_change_count,
        f.stats_summary
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) f;
END;
$function$
```
