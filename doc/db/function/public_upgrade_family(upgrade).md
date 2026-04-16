```sql
CREATE OR REPLACE FUNCTION public.upgrade_family(u upgrade)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT public.version_family(COALESCE(
        (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
        u.tags[array_upper(u.tags, 1)]
    ))
$function$
```
