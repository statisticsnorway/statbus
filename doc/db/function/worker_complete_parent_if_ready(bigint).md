```sql
CREATE OR REPLACE FUNCTION worker.complete_parent_if_ready(p_child_task_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent_id BIGINT;
    v_parent_command TEXT;
    v_child_command TEXT;
    v_parent_completed BOOLEAN := FALSE;
    v_any_failed BOOLEAN;
    v_parent_on_child_completed TEXT;
    v_parent_after_procedure TEXT;
BEGIN
    -- Get the parent_id and child command from the child task
    SELECT parent_id, command INTO v_parent_id, v_child_command
    FROM worker.tasks
    WHERE id = p_child_task_id;

    -- If no parent, nothing to do
    IF v_parent_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get parent command, lifecycle hook, and after_procedure
    SELECT t.command, cr.on_child_completed, cr.after_procedure
    INTO v_parent_command, v_parent_on_child_completed, v_parent_after_procedure
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.id = v_parent_id;

    -- Lifecycle hook: on_child_completed (generic — no domain knowledge)
    IF v_parent_on_child_completed IS NOT NULL THEN
      EXECUTE format('CALL %s', v_parent_on_child_completed)
      USING v_parent_id;
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

    IF v_any_failed THEN
        -- Parent fails because a child failed
        UPDATE worker.tasks
        SET state = 'failed',
            completed_at = clock_timestamp(),
            error = 'One or more child tasks failed'
        WHERE id = v_parent_id AND state = 'waiting';
    ELSE
        -- All children succeeded - parent completes
        UPDATE worker.tasks
        SET state = 'completed',
            completed_at = clock_timestamp()
        WHERE id = v_parent_id AND state = 'waiting';
    END IF;

    IF FOUND THEN
        v_parent_completed := TRUE;
        RAISE DEBUG 'complete_parent_if_ready: Parent task % completed (failed=%)', v_parent_id, v_any_failed;

        -- Fire parent's after_procedure now that task is truly complete.
        -- process_tasks skips after_procedure for 'waiting' tasks, so this
        -- is where parent tasks get their after_procedure called.
        IF v_parent_after_procedure IS NOT NULL THEN
          BEGIN
            RAISE DEBUG 'Calling after_procedure: % for completed parent task %', v_parent_after_procedure, v_parent_id;
            EXECUTE format('CALL %s()', v_parent_after_procedure);
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error in after_procedure % for parent task %: %', v_parent_after_procedure, v_parent_id, SQLERRM;
          END;
        END IF;
    END IF;

    RETURN v_parent_completed;
END;
$function$
```
