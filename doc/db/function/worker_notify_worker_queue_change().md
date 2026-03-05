```sql
CREATE OR REPLACE FUNCTION worker.notify_worker_queue_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM pg_notify('worker_queue_change', NEW.queue);
  RETURN NEW;
END;
$function$
```
