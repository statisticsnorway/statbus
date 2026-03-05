```sql
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    -- 2-arg overload: no round_priority_base, falls through to column default
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$function$
```
