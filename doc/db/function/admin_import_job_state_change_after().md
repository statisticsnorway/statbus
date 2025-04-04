```sql
CREATE OR REPLACE FUNCTION admin.import_job_state_change_after()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only enqueue for processing when transitioning from user action states
    -- or when a state change happens that requires further processing
    IF (OLD.state = 'waiting_for_upload' AND NEW.state = 'upload_completed') OR
       (OLD.state = 'waiting_for_review' AND NEW.state = 'approved') THEN
        PERFORM admin.enqueue_import_job_process(NEW.id);
    END IF;

    RETURN NEW;
END;
$function$
```
