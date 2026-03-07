```sql
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_legal_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only schedule collection if any changed row has a PG assigned.
    -- During initial import, LR rows are inserted with derived_power_group_id = NULL,
    -- then process_power_group_link assigns PG IDs (triggering this again).
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE derived_power_group_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Standard scheduling logic (same as ensure_collect_changes)
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
