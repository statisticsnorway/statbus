```sql
CREATE OR REPLACE FUNCTION public.country_hierarchy(country_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object('country', to_jsonb(s.*)) AS data
          FROM public.country AS s
         WHERE country_id IS NOT NULL AND s.id = country_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
