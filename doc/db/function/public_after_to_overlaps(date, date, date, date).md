```sql
CREATE OR REPLACE FUNCTION public.after_to_overlaps(a_after date, a_to date, b_after date, b_to date)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT daterange(a_after, a_to, '(]') && daterange(b_after, b_to, '(]');
$function$
```
