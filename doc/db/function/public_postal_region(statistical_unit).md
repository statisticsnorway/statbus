```sql
CREATE OR REPLACE FUNCTION public.postal_region(statistical_unit statistical_unit)
 RETURNS SETOF region
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT r.*
    FROM public.region r
    WHERE r.id = statistical_unit.postal_region_id;
$function$
```
