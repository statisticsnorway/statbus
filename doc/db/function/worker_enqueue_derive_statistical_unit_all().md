```sql
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit_all()
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id bigint;
BEGIN
    -- An empty database has nothing to derive. Scheduling nothing keeps the
    -- seed and test template, built by migrating an empty database, free of a
    -- pending task.
    IF NOT EXISTS (
        SELECT 1 FROM public.establishment
        UNION ALL SELECT 1 FROM public.legal_unit
        UNION ALL SELECT 1 FROM public.enterprise
        UNION ALL SELECT 1 FROM public.power_group
        LIMIT 1
    ) THEN
        RETURN NULL;
    END IF;

    -- One pending collect_changes is allowed (idx_tasks_collect_changes_dedup).
    -- A pending drain-mode task is upgraded to the full request: the full
    -- derive covers every change the log holds.
    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', jsonb_build_object(
        'command',                 'collect_changes',
        'establishment_id_ranges', NULL,
        'legal_unit_id_ranges',    NULL,
        'enterprise_id_ranges',    NULL,
        'power_group_id_ranges',   NULL,
        'valid_ranges',            '{[-infinity,infinity)}'
    ))
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO UPDATE SET payload = EXCLUDED.payload
    RETURNING id INTO v_task_id;

    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN v_task_id;
END;
$function$
```
