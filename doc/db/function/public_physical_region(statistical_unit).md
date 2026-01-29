```sql
CREATE OR REPLACE FUNCTION public.physical_region(statistical_unit statistical_unit)
 RETURNS SETOF region
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT r.*
    FROM public.region r
    WHERE r.id = statistical_unit.physical_region_id;
$function$
```
