```sql
CREATE OR REPLACE FUNCTION public.upgrade_family(u upgrade)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT public.version_family(COALESCE(
        (SELECT t FROM unnest(u.commit_tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
        u.commit_tags[array_upper(u.commit_tags, 1)]
    ))
$function$
```
