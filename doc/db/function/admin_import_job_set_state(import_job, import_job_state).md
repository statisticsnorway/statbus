```sql
CREATE OR REPLACE FUNCTION admin.import_job_set_state(job import_job, new_state import_job_state)
 RETURNS import_job
 LANGUAGE plpgsql
AS $function$
DECLARE
    updated_job public.import_job;
BEGIN
    -- Update the state in the database
    UPDATE public.import_job
    SET state = new_state
    WHERE id = job.id
    RETURNING * INTO updated_job;

    -- Return the updated record
    RETURN updated_job;
END;
$function$
```
