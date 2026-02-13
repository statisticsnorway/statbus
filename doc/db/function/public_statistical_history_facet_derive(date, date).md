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

    -- Bulk INSERT using LATERAL join - much faster than FOR LOOP
    INSERT INTO public.statistical_history_facet
    SELECT f.*
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) f;
END;
$function$
```
