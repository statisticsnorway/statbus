```sql
CREATE OR REPLACE FUNCTION worker.spawn(p_command text, p_payload jsonb DEFAULT '{}'::jsonb, p_parent_id bigint DEFAULT NULL::bigint, p_priority bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
BEGIN
    -- Use provided priority or get default from command registry
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
    
    INSERT INTO worker.tasks (command, payload, parent_id, priority)
    VALUES (p_command, p_payload, p_parent_id, v_priority)
    RETURNING id INTO v_task_id;
    
    -- Get the queue for notification
    PERFORM pg_notify('worker_tasks', (
        SELECT queue FROM worker.command_registry WHERE command = p_command
    ));
    
    RETURN v_task_id;
END;
$function$
```
