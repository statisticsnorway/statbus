```sql
CREATE OR REPLACE FUNCTION public.quality_relation_derive()
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    SELECT public.quality_relation_derive(int4range(0, 16384));
$function$
```
