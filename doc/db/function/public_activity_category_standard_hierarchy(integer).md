```sql
CREATE OR REPLACE FUNCTION public.activity_category_standard_hierarchy(standard_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object(
                'activity_category_standard',
                    to_jsonb(acs.*)
                ) AS data
          FROM public.activity_category_standard AS acs
         WHERE standard_id IS NOT NULL AND acs.id = standard_id
         ORDER BY acs.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
