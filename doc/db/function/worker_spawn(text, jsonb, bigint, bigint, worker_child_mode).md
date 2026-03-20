```sql
CREATE OR REPLACE FUNCTION worker.spawn(p_command text, p_payload jsonb DEFAULT '{}'::jsonb, p_parent_id bigint DEFAULT NULL::bigint, p_priority bigint DEFAULT NULL::bigint, p_child_mode worker.child_mode DEFAULT NULL::worker.child_mode)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_depth INT;
BEGIN
    IF p_priority IS NOT NULL THEN
        v_priority := p_priority;
    ELSE
        v_priority := nextval('public.worker_task_priority_seq');
    END IF;

    -- Add command to payload if not present
    IF p_payload IS NULL OR p_payload = '{}'::jsonb THEN
        p_payload := jsonb_build_object('command', p_command);
    ELSIF p_payload->>'command' IS NULL THEN
        p_payload := p_payload || jsonb_build_object('command', p_command);
    END IF;

    -- Calculate depth from parent
    IF p_parent_id IS NOT NULL THEN
        SELECT depth + 1 INTO v_depth FROM worker.tasks WHERE id = p_parent_id;
        IF v_depth IS NULL THEN
            RAISE EXCEPTION 'Parent task % not found', p_parent_id;
        END IF;

        -- Set parent's child_mode if not already set (defaults to 'concurrent')
        UPDATE worker.tasks
        SET child_mode = COALESCE(p_child_mode, 'concurrent')
        WHERE id = p_parent_id AND child_mode IS NULL;

        -- Fail fast if caller requests a mode that conflicts with what's already set
        IF p_child_mode IS NOT NULL THEN
            DECLARE
                v_existing_child_mode worker.child_mode;
            BEGIN
                SELECT child_mode INTO v_existing_child_mode
                FROM worker.tasks WHERE id = p_parent_id;
                IF v_existing_child_mode != p_child_mode THEN
                    RAISE EXCEPTION 'Parent task % already has child_mode=%, cannot set to %',
                        p_parent_id, v_existing_child_mode, p_child_mode;
                END IF;
            END;
        END IF;
    ELSE
        v_depth := 0;
    END IF;

    INSERT INTO worker.tasks (command, payload, parent_id, priority, depth)
    VALUES (p_command, p_payload, p_parent_id, v_priority, v_depth)
    RETURNING id INTO v_task_id;

    PERFORM pg_notify('worker_tasks', (
        SELECT queue FROM worker.command_registry WHERE command = p_command
    ));

    RETURN v_task_id;
END;
$function$
```
