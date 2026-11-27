```sql
CREATE OR REPLACE FUNCTION public.in_use(quality_check)
 RETURNS boolean
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
    SELECT $1.stat_definition_id IS NULL
        OR EXISTS (SELECT 1 FROM public.stat_definition AS sd
                   WHERE sd.id = $1.stat_definition_id
                     AND sd.enabled
                     AND sd.type IN ('int', 'float')
                     AND sd.lu_es_rollup = 'max')
$function$
```
