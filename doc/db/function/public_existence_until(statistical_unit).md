```sql
CREATE OR REPLACE FUNCTION public.existence_until(statistical_unit)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT public.unit_existence_until($1.valid_until, $1.death_date)
$function$
```
