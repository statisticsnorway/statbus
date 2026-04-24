```sql
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    RAISE NOTICE 'upgrade_notify_daemon: commit_sha=%', NEW.commit_sha;
    PERFORM pg_notify('upgrade_apply', NEW.commit_sha);
  END IF;
  RETURN NEW;
END;
$function$
```
