```sql
CREATE OR REPLACE FUNCTION worker.begin_deferred_base_change_wakeup()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_previous jsonb := jsonb_build_object(
        'scope', current_setting('statbus.defer_base_change_wakeup', true),
        'dirty', current_setting('statbus.base_change_wakeup_dirty', true)
    );
BEGIN
    PERFORM set_config('statbus.defer_base_change_wakeup', 'on', true);
    PERFORM set_config('statbus.base_change_wakeup_dirty', 'off', true);
    RETURN v_previous;
END;
$function$
```
