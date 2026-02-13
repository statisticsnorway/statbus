```sql
CREATE OR REPLACE FUNCTION public.statistical_history_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Insert year-resolution rows.
    -- ON CONFLICT DO UPDATE: if a concurrent worker already inserted,
    -- overwrite with the freshest computed data.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, unit_type) WHERE resolution = 'year'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;

    -- Insert year-month resolution rows.
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := 'year-month'::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h
    ON CONFLICT (resolution, year, month, unit_type) WHERE resolution = 'year-month'::public.history_resolution
    DO UPDATE SET
        exists_count = EXCLUDED.exists_count,
        exists_change = EXCLUDED.exists_change,
        exists_added_count = EXCLUDED.exists_added_count,
        exists_removed_count = EXCLUDED.exists_removed_count,
        countable_count = EXCLUDED.countable_count,
        countable_change = EXCLUDED.countable_change,
        countable_added_count = EXCLUDED.countable_added_count,
        countable_removed_count = EXCLUDED.countable_removed_count,
        births = EXCLUDED.births,
        deaths = EXCLUDED.deaths,
        name_change_count = EXCLUDED.name_change_count,
        primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
        secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
        sector_change_count = EXCLUDED.sector_change_count,
        legal_form_change_count = EXCLUDED.legal_form_change_count,
        physical_region_change_count = EXCLUDED.physical_region_change_count,
        physical_country_change_count = EXCLUDED.physical_country_change_count,
        physical_address_change_count = EXCLUDED.physical_address_change_count,
        stats_summary = EXCLUDED.stats_summary;
END;
$function$
```
