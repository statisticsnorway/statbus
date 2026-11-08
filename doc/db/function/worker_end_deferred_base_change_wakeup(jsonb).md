```sql
CREATE OR REPLACE FUNCTION worker.end_deferred_base_change_wakeup(p_previous_state jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_dirty boolean := current_setting('statbus.base_change_wakeup_dirty', true) = 'on';
BEGIN
    IF p_previous_state IS NULL OR NOT p_previous_state ?& ARRAY['scope', 'dirty'] THEN
        RAISE EXCEPTION 'Missing deferred base-change wakeup scope state';
    END IF;

    PERFORM set_config('statbus.defer_base_change_wakeup', COALESCE(p_previous_state->>'scope', ''), true);
    PERFORM set_config('statbus.base_change_wakeup_dirty', COALESCE(p_previous_state->>'dirty', ''), true);
    IF v_dirty THEN
        IF p_previous_state->>'scope' = 'on' THEN
            -- A nested scope contributes its dirty changes to its caller.
            PERFORM set_config('statbus.base_change_wakeup_dirty', 'on', true);
        ELSE
            PERFORM worker.publish_base_change_wakeup();
        END IF;
    END IF;
END;
$function$
```
