```sql
CREATE OR REPLACE FUNCTION worker.publish_base_change_wakeup()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Serialize publication with a collector before it takes its drain snapshot:
    -- lock the flag's single row every time, then set the flag only when it is
    -- off. The lock is the race guard (STATBUS-591); the UPDATE names the row it
    -- changes (STATBUS-604).
    PERFORM 1 FROM worker.base_change_log_has_pending FOR UPDATE;
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE
    WHERE NOT has_pending;

    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
END;
$function$
```
