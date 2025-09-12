```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_facet_derive(valid_from date DEFAULT '-infinity'::date, valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(valid_from=%, valid_until=%)', valid_from, valid_until;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE from_until_overlaps(suf.valid_from, suf.valid_until,
                          statistical_unit_facet_derive.valid_from,
                          statistical_unit_facet_derive.valid_until);

    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_until_overlaps(sufd.valid_from, sufd.valid_until,
                          statistical_unit_facet_derive.valid_from,
                          statistical_unit_facet_derive.valid_until);
END;
$function$
```
