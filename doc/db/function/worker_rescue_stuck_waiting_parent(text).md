```sql
CREATE OR REPLACE FUNCTION worker.rescue_stuck_waiting_parent(p_queue text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent_id BIGINT;
    v_any_child_id BIGINT;
BEGIN
    -- Find deepest stuck parent: waiting with no pending children
    SELECT t.id INTO v_parent_id
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND cr.queue = p_queue
      AND NOT worker.has_pending_children(t.id)
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1
    FOR UPDATE OF t SKIP LOCKED;

    IF v_parent_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get any child to pass to complete_parent_if_ready
    SELECT id INTO v_any_child_id
    FROM worker.tasks
    WHERE parent_id = v_parent_id
    LIMIT 1;

    IF v_any_child_id IS NULL THEN
        -- Waiting with no children is an invalid state — force-fail the parent
        UPDATE worker.tasks
        SET state = 'failed', completed_at = clock_timestamp(),
            error = 'Stuck waiting with no children (rescued)'
        WHERE id = v_parent_id AND state = 'waiting';
        RETURN v_parent_id;
    END IF;

    -- Delegate to the standard completion path (handles after_procedure + recursion)
    PERFORM worker.complete_parent_if_ready(v_any_child_id);

    RETURN v_parent_id;
END;
$function$
```
