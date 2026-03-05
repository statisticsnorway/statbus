```sql
CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_children_created(IN p_phase worker.pipeline_phase, IN p_parent_task_id bigint, IN p_child_count integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_parent_command TEXT;
BEGIN
    -- Look up the parent command for the step field
    SELECT command INTO v_parent_command
    FROM worker.tasks WHERE id = p_parent_task_id;

    -- Only set step if the command has a pipeline_step_weight entry
    -- (non-weighted commands like statistical_unit_refresh_batch should not overwrite step)
    IF EXISTS (SELECT 1 FROM worker.pipeline_step_weight WHERE step = v_parent_command AND phase = p_phase) THEN
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            step = v_parent_command,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    ELSE
        UPDATE worker.pipeline_progress
        SET total = total + p_child_count,
            updated_at = clock_timestamp()
        WHERE phase = p_phase;
    END IF;
END;
$procedure$
```
