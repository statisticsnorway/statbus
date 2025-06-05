```sql
CREATE OR REPLACE FUNCTION public.unit_size_hierarchy(unit_size_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object('unit_size', to_jsonb(us.*)) AS data
          FROM public.unit_size AS us
         WHERE unit_size_id IS NOT NULL AND us.id = unit_size_id
         ORDER BY us.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
