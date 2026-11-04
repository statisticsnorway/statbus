```sql
CREATE OR REPLACE PROCEDURE worker.derive_history_delta_range(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_hash_range int4range := (payload->>'hash_range')::int4range;
    v_rebuild boolean := COALESCE((payload->>'rebuild')::boolean, false);
BEGIN
    CALL worker.history_delta_range(p_hash_range => v_hash_range, p_rebuild => v_rebuild);
    p_info := jsonb_build_object('hash_range', v_hash_range::text, 'rebuild', v_rebuild);
END;
$procedure$
```
