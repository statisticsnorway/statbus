```sql
CREATE OR REPLACE FUNCTION public.jsonb_stats_lu_es_rollup(own jsonb, parts jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
    -- Per stat: 'max' takes the summary with the larger sum (public.jsonb_stats_covers), 'sum' adds the
    -- two (public.jsonb_stats_merge); a stat held on one level only is that level's summary either way.
    SELECT CASE
        WHEN jsonb_stats_lu_es_rollup.own IS NULL THEN jsonb_stats_lu_es_rollup.parts
        WHEN jsonb_stats_lu_es_rollup.parts IS NULL THEN jsonb_stats_lu_es_rollup.own
        ELSE (
            SELECT jsonb_object_agg(k.key,
                CASE
                    WHEN k.key = 'type' THEN coalesce(jsonb_stats_lu_es_rollup.own->'type', jsonb_stats_lu_es_rollup.parts->'type')
                    WHEN NOT jsonb_stats_lu_es_rollup.own ? k.key THEN jsonb_stats_lu_es_rollup.parts->k.key
                    WHEN NOT jsonb_stats_lu_es_rollup.parts ? k.key THEN jsonb_stats_lu_es_rollup.own->k.key
                    WHEN COALESCE(sd.lu_es_rollup, 'sum') = 'sum'
                         AND (jsonb_stats_lu_es_rollup.own->k.key) ? 'sum' AND (jsonb_stats_lu_es_rollup.parts->k.key) ? 'sum'
                        THEN public.jsonb_stats_merge(
                                 jsonb_build_object('type', jsonb_stats_lu_es_rollup.own->'type', k.key, jsonb_stats_lu_es_rollup.own->k.key),
                                 jsonb_build_object('type', jsonb_stats_lu_es_rollup.parts->'type', k.key, jsonb_stats_lu_es_rollup.parts->k.key))->k.key
                    ELSE public.jsonb_stats_covers(
                             jsonb_build_object('type', jsonb_stats_lu_es_rollup.own->'type', k.key, jsonb_stats_lu_es_rollup.own->k.key),
                             jsonb_build_object('type', jsonb_stats_lu_es_rollup.parts->'type', k.key, jsonb_stats_lu_es_rollup.parts->k.key))->k.key
                END)
            FROM (SELECT jsonb_object_keys(jsonb_stats_lu_es_rollup.own) AS key
                  UNION
                  SELECT jsonb_object_keys(jsonb_stats_lu_es_rollup.parts)) AS k
            LEFT JOIN public.stat_definition AS sd ON sd.code = k.key)
    END
$function$
```
