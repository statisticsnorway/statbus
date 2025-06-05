```sql
CREATE OR REPLACE FUNCTION admin.import_job_next_state(job import_job)
 RETURNS import_job_state
 LANGUAGE plpgsql
AS $function$
BEGIN
    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RETURN job.state; -- No automatic transition, requires user action

        WHEN 'upload_completed' THEN
            RETURN 'preparing_data';

        WHEN 'preparing_data' THEN
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'analysing_data' THEN
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'waiting_for_review' THEN
          RETURN job.state; -- No automatic transition, requires user action

        WHEN 'approved' THEN
            RETURN 'processing_data';

        WHEN 'rejected' THEN
            RETURN 'finished';

        WHEN 'processing_data' THEN
            RETURN job.state; -- Transition done by batch job as it completes.

        WHEN 'finished' THEN
            RETURN job.state; -- Terminal state

        ELSE
            RAISE EXCEPTION 'Unknown import job state: %', job.state;
    END CASE;
END;
$function$
```
