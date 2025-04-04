```sql
CREATE OR REPLACE FUNCTION public.array_distinct_concat_final(anycompatiblearray)
 RETURNS anycompatiblearray
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
SELECT array_agg(DISTINCT elem)
  FROM unnest($1) as elem;
$function$
```
