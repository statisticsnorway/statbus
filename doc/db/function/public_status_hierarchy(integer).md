```sql
CREATE OR REPLACE FUNCTION public.status_hierarchy(status_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object('status', to_jsonb(s.*)) AS data
          FROM public.status AS s
         WHERE status_id IS NOT NULL AND s.id = status_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
