```sql
CREATE OR REPLACE FUNCTION public.upgrade_notify_frontend()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM pg_notify('worker_status', '{"type":"upgrade_changed"}');
  RETURN COALESCE(NEW, OLD);
END;
$function$
```
