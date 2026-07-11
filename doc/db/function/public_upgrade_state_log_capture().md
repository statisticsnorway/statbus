```sql
CREATE OR REPLACE FUNCTION public.upgrade_state_log_capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO public.upgrade_state_log (
    upgrade_id, old_state, new_state, old_parked_at, new_parked_at,
    application_name, query, backend_pid, logged_at)
  VALUES (
    NEW.id, OLD.state, NEW.state, OLD.recovery_parked_at, NEW.recovery_parked_at,
    current_setting('application_name', true), current_query(),
    pg_backend_pid(), clock_timestamp());
  RETURN NEW;
END;
$function$
```
