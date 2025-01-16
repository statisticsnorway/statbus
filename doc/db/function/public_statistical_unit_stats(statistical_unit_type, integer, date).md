```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_stats(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit_stats
 LANGUAGE sql
 STABLE
AS $function$
    SELECT unit_type, unit_id, valid_from, valid_to, stats, stats_summary FROM public.relevant_statistical_units(unit_type, unit_id, valid_on);
$function$
```
