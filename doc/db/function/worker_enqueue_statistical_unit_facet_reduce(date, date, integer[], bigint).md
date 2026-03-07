```sql
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_dirty_partitions integer[] DEFAULT NULL::integer[], p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until,
        'dirty_partitions', p_dirty_partitions,
        'round_priority_base', v_priority
    ), v_priority)
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
            'dirty_partitions', CASE
                WHEN t.payload->'dirty_partitions' = 'null'::jsonb
                  OR EXCLUDED.payload->'dirty_partitions' = 'null'::jsonb
                THEN NULL
                ELSE (
                    SELECT jsonb_agg(DISTINCT val ORDER BY val)
                    FROM (
                        SELECT jsonb_array_elements(t.payload->'dirty_partitions') AS val
                        UNION
                        SELECT jsonb_array_elements(EXCLUDED.payload->'dirty_partitions') AS val
                    ) AS combined
                )
            END,
            'round_priority_base', LEAST(
                (t.payload->>'round_priority_base')::bigint,
                (EXCLUDED.payload->>'round_priority_base')::bigint
            )
        ),
        state = 'pending'::worker.task_state,
        priority = LEAST(t.priority, EXCLUDED.priority)
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$function$
```
