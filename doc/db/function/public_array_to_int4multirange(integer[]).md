```sql
CREATE OR REPLACE FUNCTION public.array_to_int4multirange(p_array integer[])
 RETURNS int4multirange
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT range_agg(int4range(id, id, '[]')) FROM unnest(p_array) as t(id);
$function$
```
