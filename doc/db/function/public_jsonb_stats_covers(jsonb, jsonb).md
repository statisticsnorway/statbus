```sql
CREATE OR REPLACE FUNCTION public.jsonb_stats_covers(own jsonb, parts jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT CASE
        WHEN jsonb_stats_covers.own IS NULL THEN jsonb_stats_covers.parts
        WHEN jsonb_stats_covers.parts IS NULL THEN jsonb_stats_covers.own
        ELSE (
            SELECT jsonb_object_agg(k.key,
                CASE
                    WHEN k.key = 'type' THEN coalesce(jsonb_stats_covers.own->'type', jsonb_stats_covers.parts->'type')
                    WHEN NOT jsonb_stats_covers.own ? k.key THEN jsonb_stats_covers.parts->k.key
                    WHEN NOT jsonb_stats_covers.parts ? k.key THEN jsonb_stats_covers.own->k.key
                    WHEN (jsonb_stats_covers.own->k.key) ? 'sum' AND (jsonb_stats_covers.parts->k.key) ? 'sum'
                         AND (jsonb_stats_covers.own->k.key->>'sum')::numeric < (jsonb_stats_covers.parts->k.key->>'sum')::numeric
                        THEN jsonb_stats_covers.parts->k.key
                    ELSE jsonb_stats_covers.own->k.key
                END)
            FROM (SELECT jsonb_object_keys(jsonb_stats_covers.own) AS key
                  UNION
                  SELECT jsonb_object_keys(jsonb_stats_covers.parts)) AS k)
    END
$function$
```
