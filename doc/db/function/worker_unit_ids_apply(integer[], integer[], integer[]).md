```sql
CREATE OR REPLACE FUNCTION worker.unit_ids_apply(p_ids integer[], p_plus integer[], p_minus integer[])
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT COALESCE(array_agg(id ORDER BY id), '{}') FROM (
        SELECT id FROM (SELECT unnest(p_ids) AS id, 1 AS n
                        UNION ALL SELECT unnest(p_plus), 1
                        UNION ALL SELECT unnest(p_minus), -1) AS x
         GROUP BY id HAVING sum(n) > 0) AS y
$function$
```
