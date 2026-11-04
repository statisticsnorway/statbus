```sql
CREATE OR REPLACE FUNCTION public.int_array_add(a integer[], b integer[])
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
AS $function$
    SELECT array_agg(COALESCE(x, 0) + COALESCE(y, 0) ORDER BY i) FROM unnest(a, b) WITH ORDINALITY AS z(x, y, i)
$function$
```
