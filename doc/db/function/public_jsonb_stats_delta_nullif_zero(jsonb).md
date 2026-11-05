```sql
CREATE OR REPLACE FUNCTION public.jsonb_stats_delta_nullif_zero(p_delta jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT CASE WHEN p_delta IS NULL
                  OR NOT EXISTS (SELECT 1 FROM jsonb_each(p_delta - 'type') AS e
                                  WHERE e.value->'in' IS DISTINCT FROM e.value->'out')
                THEN NULL ELSE p_delta END
$function$
```
