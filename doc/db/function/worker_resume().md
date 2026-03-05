```sql
CREATE OR REPLACE FUNCTION worker.resume()
 RETURNS void
 LANGUAGE sql
AS $function$
  SELECT pg_notify('worker_control', 'resume');
$function$
```
