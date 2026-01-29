```sql
CREATE OR REPLACE FUNCTION public.physical_country(statistical_unit statistical_unit)
 RETURNS SETOF country
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT c.*
    FROM public.country c
    WHERE c.id = statistical_unit.physical_country_id;
$function$
```
