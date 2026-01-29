```sql
CREATE OR REPLACE FUNCTION public.status(statistical_unit statistical_unit)
 RETURNS SETOF status
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT st.*
    FROM public.status st
    WHERE st.id = statistical_unit.status_id;
$function$
```
