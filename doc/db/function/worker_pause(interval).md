```sql
CREATE OR REPLACE FUNCTION worker.pause(p_duration interval)
 RETURNS void
 LANGUAGE sql
AS $function$
  SELECT worker.pause(EXTRACT(EPOCH FROM p_duration)::bigint);
$function$
```
