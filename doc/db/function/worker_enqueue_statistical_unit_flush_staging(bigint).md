```sql
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_flush_staging(p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_payload JSONB;
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
    v_payload := jsonb_build_object(
        'command', 'statistical_unit_flush_staging',
        'round_priority_base', v_priority
    );

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_unit_flush_staging', v_payload, v_priority)
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_flush_staging' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_flush_staging',
            'round_priority_base', LEAST(
                (t.payload->>'round_priority_base')::bigint,
                (EXCLUDED.payload->>'round_priority_base')::bigint
            )
        ),
        priority = LEAST(t.priority, EXCLUDED.priority)
    RETURNING id INTO v_task_id;

    PERFORM pg_notify('worker_tasks', 'analytics');

    RETURN v_task_id;
END;
$function$
```
