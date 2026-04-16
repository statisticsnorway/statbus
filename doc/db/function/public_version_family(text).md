```sql
CREATE OR REPLACE FUNCTION public.version_family(tag text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT split_part(tag, '-', 1)
$function$
```
