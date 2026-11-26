```sql
CREATE OR REPLACE FUNCTION public.quality_check_starting_set()
 RETURNS SETOF quality_rule
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT unnest(ARRAY['missing_region', 'missing_activity_category', 'secondary_activity_equals_primary']::public.quality_rule[])
$function$
```
