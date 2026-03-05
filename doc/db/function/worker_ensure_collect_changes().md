```sql
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Set LOGGED flag for crash recovery (no-op if already TRUE)
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE WHERE has_pending = FALSE;

    -- Enqueue collect_changes task (DO NOTHING = no row lock!)
    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    -- pg_notify fires even when ON CONFLICT DO NOTHING matches (PG provides
    -- no way to detect this). Cost is negligible: worker wakes, finds nothing, sleeps.
    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$function$
```
