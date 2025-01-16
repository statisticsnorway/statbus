```sql
CREATE OR REPLACE FUNCTION public.region_hierarchy(region_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object('region', to_jsonb(s.*)) AS data
          FROM public.region AS s
         WHERE region_id IS NOT NULL AND s.id = region_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
