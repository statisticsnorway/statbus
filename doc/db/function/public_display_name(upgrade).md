```sql
CREATE OR REPLACE FUNCTION public.display_name(u upgrade)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    (SELECT t FROM unnest(u.commit_tags) AS t WHERE t NOT LIKE '%-%' LIMIT 1),
    u.commit_tags[array_upper(u.commit_tags, 1)],
    left(u.commit_sha, 8)
  );
$function$
```
