```sql
CREATE OR REPLACE FUNCTION public.upgrade_notify_daemon()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_payload text;
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND (OLD.scheduled_at IS NULL OR OLD.scheduled_at != NEW.scheduled_at) THEN
    v_payload := 'sha-' || NEW.commit_sha;
    RAISE NOTICE 'upgrade_notify_daemon: sha=% payload=%', NEW.commit_sha, v_payload;
    PERFORM pg_notify('upgrade_apply', v_payload);
  END IF;
  RETURN NEW;
END;
$function$
```
