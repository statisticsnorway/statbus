```sql
CREATE OR REPLACE PROCEDURE worker.derive_reports(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    RAISE WARNING 'derive_reports called but is now a no-op — use derive_reports_phase instead';
END;
$procedure$
```
