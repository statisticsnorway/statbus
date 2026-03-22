```sql
CREATE OR REPLACE PROCEDURE worker.derive_reports_phase(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', true)::text);
    -- Partition count is now fixed at 256 — no dynamic adjustment needed.
    -- (Removed: CALL admin.adjust_analytics_partition_count())

    p_info := jsonb_build_object(
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    );
    -- Add year count only when both dates are finite
    IF isfinite(v_valid_from) AND isfinite(v_valid_until) THEN
        p_info := p_info || jsonb_build_object(
            'years', EXTRACT(YEAR FROM v_valid_until)::int - EXTRACT(YEAR FROM v_valid_from)::int
        );
    END IF;
END;
$procedure$
```
