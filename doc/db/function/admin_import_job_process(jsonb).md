```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN payload jsonb)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    job_id INTEGER;
BEGIN
    -- Extract job_id from payload and call the implementation procedure
    job_id := (payload->>'job_id')::INTEGER;

    -- Call the implementation procedure
    CALL admin.import_job_process(job_id);
END;
$procedure$
```
