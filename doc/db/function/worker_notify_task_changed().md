```sql
CREATE OR REPLACE FUNCTION worker.notify_task_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'worker', 'pg_temp'
AS $function$
BEGIN
    -- Only notify on actual state changes, not every UPDATE
    IF OLD.state IS DISTINCT FROM NEW.state THEN
        PERFORM pg_notify('worker_task_changed',
            json_build_object(
                'id', NEW.id,
                'parent_id', NEW.parent_id
            )::text
        );
    END IF;
    RETURN NEW;
END;
$function$
```
