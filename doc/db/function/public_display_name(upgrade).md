```sql
CREATE OR REPLACE FUNCTION public.display_name(u upgrade)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    (SELECT t FROM unnest(u.tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
    u.tags[array_upper(u.tags, 1)],
    'sha-' || left(u.commit_sha, 12)
  );
$function$
```
