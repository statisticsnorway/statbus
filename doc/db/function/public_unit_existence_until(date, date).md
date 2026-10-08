```sql
CREATE OR REPLACE FUNCTION public.unit_existence_until(valid_until date, death_date date)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT LEAST(valid_until, death_date)
$function$
```
