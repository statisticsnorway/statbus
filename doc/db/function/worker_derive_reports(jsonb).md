```sql
CREATE OR REPLACE PROCEDURE worker.derive_reports(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
BEGIN
  -- Call the reports refresh function with the extracted parameters
  PERFORM worker.derive_reports(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until,
    p_round_priority_base := v_round_priority_base
  );
END;
$procedure$
```
