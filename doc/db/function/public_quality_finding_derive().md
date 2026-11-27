```sql
CREATE OR REPLACE FUNCTION public.quality_finding_derive()
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    SELECT public.quality_finding_derive(int4range(0, 16384));
$function$
```
