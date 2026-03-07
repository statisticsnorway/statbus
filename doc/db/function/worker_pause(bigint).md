```sql
CREATE OR REPLACE FUNCTION worker.pause(p_seconds bigint)
 RETURNS void
 LANGUAGE sql
AS $function$
  SELECT pg_notify('worker_control', 'pause:' || p_seconds::text);
$function$
```
