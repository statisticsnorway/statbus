```sql
CREATE OR REPLACE FUNCTION worker.complete_parent_if_ready(p_child_task_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent_id BIGINT;
    v_parent_completed BOOLEAN := FALSE;
    v_any_failed BOOLEAN;
    v_parent_after_procedure TEXT;
    v_grandparent_task_id BIGINT;
BEGIN
    SELECT parent_id INTO v_parent_id
    FROM worker.tasks
    WHERE id = p_child_task_id;

    IF v_parent_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if parent still has pending children
    IF worker.has_pending_children(v_parent_id) THEN
        RETURN FALSE;
    END IF;

    -- All children done - check for failures
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE parent_id = v_parent_id AND state = 'failed'
    ) INTO v_any_failed;

    -- CONCURRENCY NOTE: Within a single worker process, multiple child fibers
    -- may call this after completing their respective children. The
    -- has_pending_children check could pass for two fibers simultaneously,
    -- but UPDATE ... WHERE state = 'waiting' acts as an optimistic lock —
    -- only one fiber's UPDATE matches, and IF FOUND guards all side effects.
    IF v_any_failed THEN
        UPDATE worker.tasks
        SET state = 'failed',
            completed_at = clock_timestamp(),
            error = 'One or more child tasks failed'
        WHERE id = v_parent_id AND state = 'waiting';
    ELSE
        UPDATE worker.tasks
        SET state = 'completed',
            completed_at = clock_timestamp()
        WHERE id = v_parent_id AND state = 'waiting';
    END IF;

    IF FOUND THEN
        v_parent_completed := TRUE;
        RAISE DEBUG 'complete_parent_if_ready: Parent task % completed (failed=%)', v_parent_id, v_any_failed;

        -- Fire parent's after_procedure
        SELECT cr.after_procedure INTO v_parent_after_procedure
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.id = v_parent_id;

        IF v_parent_after_procedure IS NOT NULL THEN
          BEGIN
            EXECUTE format('CALL %s()', v_parent_after_procedure);
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error in after_procedure % for parent task %: %', v_parent_after_procedure, v_parent_id, SQLERRM;
          END;
        END IF;

        -- RECURSIVE: Check if the parent's parent is now ready too
        -- Recursion depth bounded by task tree depth (typically 2-3 levels).
        SELECT parent_id INTO v_grandparent_task_id
        FROM worker.tasks WHERE id = v_parent_id;

        IF v_grandparent_task_id IS NOT NULL THEN
            PERFORM worker.complete_parent_if_ready(v_parent_id);
        END IF;
    END IF;

    RETURN v_parent_completed;
END;
$function$
```
