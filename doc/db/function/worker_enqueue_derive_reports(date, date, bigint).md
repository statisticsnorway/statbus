```sql
CREATE OR REPLACE FUNCTION worker.enqueue_derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_reports',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (
    command, payload, priority
  ) VALUES ('derive_reports', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_reports' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_reports',
      'valid_from', LEAST(
        (t.payload->>'valid_from')::date,
        (EXCLUDED.payload->>'valid_from')::date
      ),
      'valid_until', GREATEST(
        (t.payload->>'valid_until')::date,
        (EXCLUDED.payload->>'valid_until')::date
      ),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority),
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$
```
