```sql
CREATE OR REPLACE FUNCTION admin.import_job_state_change_after()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_blocked_job RECORD;
BEGIN
    -- Enqueue the job itself when transitioning from user action states
    IF (OLD.state = 'waiting_for_upload' AND NEW.state = 'upload_completed') OR
       (OLD.state = 'waiting_for_review' AND NEW.state = 'approved') THEN
        PERFORM admin.enqueue_import_job_process(NEW.id);
    END IF;

    -- When a review resolves (approve or reject), re-enqueue all blocked jobs.
    -- These jobs returned without rescheduling because they saw a waiting_for_review job.
    IF OLD.state = 'waiting_for_review' AND NEW.state IN ('approved', 'rejected') THEN
        FOR v_blocked_job IN
            SELECT id FROM public.import_job
            WHERE id <> NEW.id
              AND state IN ('upload_completed', 'preparing_data', 'analysing_data', 'processing_data')
            ORDER BY priority, id
        LOOP
            PERFORM admin.enqueue_import_job_process(v_blocked_job.id);
        END LOOP;
    END IF;

    RETURN NEW;
END;
$function$
```
