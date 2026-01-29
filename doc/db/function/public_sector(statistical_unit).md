```sql
CREATE OR REPLACE FUNCTION public.sector(statistical_unit statistical_unit)
 RETURNS SETOF sector
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT s.*
    FROM public.sector s
    WHERE s.id = statistical_unit.sector_id;
$function$
```
