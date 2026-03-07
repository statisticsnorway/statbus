```sql
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet_period(p_resolution history_resolution, p_year integer, p_month integer DEFAULT NULL::integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history_facet_period',
    'resolution', p_resolution::text,
    'year', p_year,
    'month', p_month  -- NULL for year resolution
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_history_facet_period', v_payload)
  ON CONFLICT (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'))
  WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending'::worker.task_state
  DO NOTHING
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$function$
```
