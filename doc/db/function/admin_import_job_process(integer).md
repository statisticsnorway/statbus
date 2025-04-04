```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator, for recording edit_by_user_id
    PERFORM admin.set_import_job_user_context(job_id);

    -- Process the job based on its current state
    -- We'll only process one state transition per transaction to ensure visibility

    -- Perform the appropriate action for the current state
    CASE job.state
    WHEN 'waiting_for_upload' THEN
        RAISE DEBUG 'Import job % is waiting for upload', job_id;
        should_reschedule := FALSE;

    WHEN 'upload_completed' THEN
        RAISE DEBUG 'Import job % is ready for preparing data', job_id;
        should_reschedule := TRUE;

    WHEN 'preparing_data' THEN
        PERFORM admin.import_job_prepare(job);
        should_reschedule := TRUE;

    WHEN 'analysing_data' THEN
        PERFORM admin.import_job_analyse(job);
        should_reschedule := TRUE;

    WHEN 'waiting_for_review' THEN
        RAISE DEBUG 'Import job % is waiting for review', job_id;
        should_reschedule := FALSE;

    WHEN 'approved' THEN
        RAISE DEBUG 'Import job % is approved for importing', job_id;
        should_reschedule := TRUE;

    WHEN 'rejected' THEN
        RAISE DEBUG 'Import job % was rejected', job_id;
        should_reschedule := FALSE;

    WHEN 'importing_data' THEN
        -- For importing, we'll handle batches in the import_job_insert function
        PERFORM admin.import_job_insert(job);

        -- Check if we need to reschedule (not finished yet)
        SELECT state = 'importing_data' INTO should_reschedule
        FROM public.import_job WHERE id = job_id;

    WHEN 'finished' THEN
        RAISE DEBUG 'Import job % completed successfully', job_id;
        should_reschedule := FALSE;

    ELSE
        RAISE WARNING 'Unknown import job state: %', job.state;
        should_reschedule := FALSE;
    END CASE;

    -- After processing the current state, calculate and set the next state
    -- Only transition if the job is still in the same state (it might have changed during processing)
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    next_state := admin.import_job_next_state(job);

    IF next_state <> job.state THEN
        -- Update the job state for the next run
        job := admin.import_job_set_state(job, next_state);
        RAISE DEBUG 'Updated import job % state from % to %', job_id, job.state, next_state;

        -- Always reschedule after a state change
        should_reschedule := TRUE;
    END IF;

    -- Reset the user context when done
    PERFORM admin.reset_import_job_user_context();

    -- Reschedule if needed
    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
        RAISE DEBUG 'Rescheduled import job % for further processing', job_id;
    END IF;
END;
$procedure$
```
