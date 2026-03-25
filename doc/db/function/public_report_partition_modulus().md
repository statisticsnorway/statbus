```sql
CREATE OR REPLACE FUNCTION public.report_partition_modulus()
 RETURNS integer
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
    SELECT report_partition_modulus FROM public.settings LIMIT 1;
$function$
```
