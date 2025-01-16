```sql
CREATE OR REPLACE FUNCTION public.activity_category_hierarchy(activity_category_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object(
            'activity_category',
                to_jsonb(ac.*)
                || (SELECT public.activity_category_standard_hierarchy(ac.standard_id))
            )
            AS data
         FROM public.activity_category AS ac
         WHERE activity_category_id IS NOT NULL AND ac.id = activity_category_id
         ORDER BY ac.path
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```
