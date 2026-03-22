```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    job_id INTEGER;
BEGIN
    job_id := (payload->>'job_id')::INTEGER;
    CALL admin.import_job_process(job_id, p_info);
END;
$procedure$
```
