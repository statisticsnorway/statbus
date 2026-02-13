```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_facet_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE from_until_overlaps(suf.valid_from, suf.valid_until,
                          p_valid_from,
                          p_valid_until);

    -- ON CONFLICT DO UPDATE: if a concurrent worker already inserted,
    -- overwrite with the freshest computed data (count + stats_summary).
    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_until_overlaps(sufd.valid_from, sufd.valid_until,
                          p_valid_from,
                          p_valid_until)
    ON CONFLICT (valid_from, valid_to, valid_until, unit_type,
                 physical_region_path, primary_activity_category_path,
                 sector_path, legal_form_id, physical_country_id, status_id)
    DO UPDATE SET
        count = EXCLUDED.count,
        stats_summary = EXCLUDED.stats_summary;
END;
$function$
```
