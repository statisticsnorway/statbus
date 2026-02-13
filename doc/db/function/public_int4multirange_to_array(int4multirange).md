```sql
CREATE OR REPLACE FUNCTION public.int4multirange_to_array(p_ranges int4multirange)
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT array_agg(id ORDER BY id)
    FROM (
        SELECT generate_series(lower(r), upper(r) - 1) AS id
        FROM unnest(p_ranges) AS r
    ) expanded;
$function$
```
