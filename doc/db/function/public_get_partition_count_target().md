```sql
CREATE OR REPLACE FUNCTION public.get_partition_count_target()
 RETURNS integer
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
    SELECT COALESCE((SELECT partition_count_target FROM public.settings LIMIT 1), 256);
$function$
```
