```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_facet_derive(valid_after date DEFAULT '-infinity'::date, valid_to date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  derived_valid_from DATE := (statistical_unit_facet_derive.valid_after + '1 DAY'::INTERVAL)::DATE;
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(valid_after=%, valid_to=%)', valid_after, valid_to;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE from_to_overlaps(suf.valid_from, suf.valid_to, 
                          derived_valid_from,
                          statistical_unit_facet_derive.valid_to);

    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_to_overlaps(sufd.valid_from, sufd.valid_to,
                          derived_valid_from,
                          statistical_unit_facet_derive.valid_to);
END;
$function$
```
