```sql
CREATE OR REPLACE FUNCTION public.primary_activity_category(statistical_unit statistical_unit)
 RETURNS SETOF activity_category
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT ac.*
    FROM public.activity_category ac
    WHERE ac.id = statistical_unit.primary_activity_category_id;
$function$
```
