```sql
CREATE OR REPLACE FUNCTION public.unit_existence_from(valid_from date, birth_date date)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT GREATEST(valid_from, birth_date)
$function$
```
