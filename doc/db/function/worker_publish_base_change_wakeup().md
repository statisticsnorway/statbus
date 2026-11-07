```sql
CREATE OR REPLACE FUNCTION worker.publish_base_change_wakeup()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Serialize publication with a collector before it takes its drain snapshot.
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE;

    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
END;
$function$
```
