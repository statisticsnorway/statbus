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
    v_children_info JSONB;
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

    -- Aggregate children's info: sum numerics, last-value for non-numerics
    -- Guard SUM with CASE to avoid casting non-numeric jsonb values
    SELECT jsonb_object_agg(key, CASE
        WHEN every_numeric THEN to_jsonb(numeric_sum)
        ELSE last_value
    END)
    INTO v_children_info
    FROM (
        SELECT key,
            bool_and(jsonb_typeof(value) = 'number') AS every_numeric,
            SUM(CASE WHEN jsonb_typeof(value) = 'number' THEN (value)::numeric ELSE 0 END) AS numeric_sum,
            (array_agg(value ORDER BY child_id DESC))[1] AS last_value
        FROM (
            SELECT c.id AS child_id, kv.key, kv.value
            FROM worker.tasks AS c,
                 jsonb_each(c.info) AS kv(key, value)
            WHERE c.parent_id = v_parent_id
              AND c.info IS NOT NULL
        ) AS expanded
        GROUP BY key
    ) AS aggregated;

    IF v_any_failed THEN
        -- Merge: children's info first, parent's own keys overwrite (right-side wins with ||)
        UPDATE worker.tasks
        SET state = 'failed',
            completed_at = clock_timestamp(),
            completion_duration_ms = EXTRACT(EPOCH FROM (clock_timestamp() - process_start_at)) * 1000,
            error = 'One or more child tasks failed',
            info = COALESCE(v_children_info, '{}'::jsonb) || COALESCE(info, '{}'::jsonb)
        WHERE id = v_parent_id AND state = 'waiting';
    ELSE
        UPDATE worker.tasks
        SET state = 'completed',
            completed_at = clock_timestamp(),
            completion_duration_ms = EXTRACT(EPOCH FROM (clock_timestamp() - process_start_at)) * 1000,
            info = COALESCE(v_children_info, '{}'::jsonb) || COALESCE(info, '{}'::jsonb)
        WHERE id = v_parent_id AND state = 'waiting';
    END IF;

    IF FOUND THEN
        v_parent_completed := TRUE;
        RAISE DEBUG 'complete_parent_if_ready: Parent task % completed (failed=%, info=%)', v_parent_id, v_any_failed, v_children_info;

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
