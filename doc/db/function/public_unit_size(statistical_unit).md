```sql
CREATE OR REPLACE FUNCTION public.unit_size(statistical_unit statistical_unit)
 RETURNS SETOF unit_size
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT us.*
    FROM public.unit_size us
    WHERE us.id = statistical_unit.unit_size_id;
$function$
```
