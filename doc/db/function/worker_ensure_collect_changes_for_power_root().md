```sql
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_power_root()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE custom_root_legal_unit_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE WHERE has_pending = FALSE;

    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$function$
```
