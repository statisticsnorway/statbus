```sql
CREATE OR REPLACE FUNCTION public.upgrade_request_check()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  NOTIFY upgrade_check;
$function$
```
