```sql
CREATE OR REPLACE FUNCTION public.get_report_partition_modulus()
 RETURNS integer
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
    SELECT COALESCE((SELECT report_partition_modulus FROM public.settings LIMIT 1), 256);
$function$
```
