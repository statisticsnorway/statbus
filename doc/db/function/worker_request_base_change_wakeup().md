```sql
CREATE OR REPLACE FUNCTION worker.request_base_change_wakeup()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('statbus.defer_base_change_wakeup', true) = 'on' THEN
        PERFORM set_config('statbus.base_change_wakeup_dirty', 'on', true);
    ELSE
        PERFORM worker.publish_base_change_wakeup();
    END IF;
END;
$function$
```
