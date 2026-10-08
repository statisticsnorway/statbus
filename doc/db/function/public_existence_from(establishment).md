```sql
CREATE OR REPLACE FUNCTION public.existence_from(establishment)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT public.unit_existence_from($1.valid_from, $1.birth_date)
$function$
```
