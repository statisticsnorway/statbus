```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
    v_processed_count INTEGER; -- Moved declaration here
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator
    PERFORM admin.set_import_job_user_context(job_id);

    RAISE DEBUG '[Job %] Processing job in state: %', job_id, job.state;

    -- Process based on current state
    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RAISE DEBUG '[Job %] Waiting for upload.', job_id;
            should_reschedule := FALSE;

        WHEN 'upload_completed' THEN
            RAISE DEBUG '[Job %] Transitioning to preparing_data.', job_id;
            job := admin.import_job_set_state(job, 'preparing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start prepare

        WHEN 'preparing_data' THEN
            RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
            PERFORM admin.import_job_prepare(job);
            -- Transition rows in _data table from 'pending' to 'analysing'
            RAISE DEBUG '[Job %] Updating data rows from pending to analysing in table %', job_id, job.data_table_name;
            EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysing'::public.import_data_state, 'pending'::public.import_data_state);
            job := admin.import_job_set_state(job, 'analysing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start analysis

        WHEN 'analysing_data' THEN
            RAISE DEBUG '[Job %] Starting analysis phase.', job_id;
            should_reschedule := admin.import_job_process_phase(job, 'analyse'::public.import_step_phase);
            
            -- Refresh job record to see if an error was set by the phase
            SELECT * INTO job FROM public.import_job WHERE id = job_id;

            IF job.error IS NOT NULL THEN
                RAISE WARNING '[Job %] Error detected during analysis phase: %. Transitioning to finished.', job_id, job.error;
                job := admin.import_job_set_state(job, 'finished');
                should_reschedule := FALSE;
            ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                IF job.review THEN
                    -- Transition rows from 'analysing' to 'analysed' if review is required
                    -- Rows in 'analysing' state here have completed all analysis steps.
                    -- The 'error' field might be populated with non-fatal errors (e.g., for legal_unit activity codes).
                    RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                    EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                    job := admin.import_job_set_state(job, 'waiting_for_review');
                    RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    -- should_reschedule remains FALSE as it's waiting for user action
                ELSE
                    -- Transition rows from 'analysing' to 'processing' if no review
                    -- Rows in 'analysing' state here have completed all analysis steps.
                    RAISE DEBUG '[Job %] Updating data rows from analysing to processing and resetting LCP in table %', job_id, job.data_table_name;
                    EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L$$, job.data_table_name, 'processing'::public.import_data_state, 'analysing'::public.import_data_state);
                    job := admin.import_job_set_state(job, 'processing_data');
                    RAISE DEBUG '[Job %] Analysis complete, proceeding to processing.', job_id;
                    should_reschedule := TRUE; -- Reschedule to start processing
                END IF;
            END IF;
            -- If should_reschedule is TRUE from the phase function (and no error), it will be rescheduled.

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
            -- Transition rows in _data table from 'analysed' to 'processing' and reset LCP
            RAISE DEBUG '[Job %] Updating data rows from analysed to processing and resetting LCP in table % after approval', job_id, job.data_table_name;
            EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L AND error IS NULL$$, job.data_table_name, 'processing'::public.import_data_state, 'analysed'::public.import_data_state);
            job := admin.import_job_set_state(job, 'processing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start import

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            RAISE DEBUG '[Job %] Starting process phase.', job_id;
            should_reschedule := admin.import_job_process_phase(job, 'process'::public.import_step_phase);

            -- Refresh job record to see if an error was set by the phase
            SELECT * INTO job FROM public.import_job WHERE id = job_id;

            IF job.error IS NOT NULL THEN
                RAISE WARNING '[Job %] Error detected during processing phase: %. Transitioning to finished.', job_id, job.error;
                job := admin.import_job_set_state(job, 'finished');
                should_reschedule := FALSE;
            ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                -- Update data rows to 'processed'
                RAISE DEBUG '[Job %] Finalizing processed rows in table %', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND error IS NULL$$, job.data_table_name, 'processed'::public.import_data_state, 'processing'::public.import_data_state);

                -- Update imported_rows count on the job
                -- DECLARE v_processed_count INTEGER; -- Declaration moved to the top of the procedure
                EXECUTE format($$SELECT count(*) FROM public.%I WHERE state = %L$$, job.data_table_name, 'processed'::public.import_data_state) INTO v_processed_count;
                UPDATE public.import_job SET imported_rows = v_processed_count WHERE id = job.id;
                RAISE DEBUG '[Job %] Updated imported_rows to %', job_id, v_processed_count;

                job := admin.import_job_set_state(job, 'finished');
                RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
                -- should_reschedule remains FALSE
            END IF;
            -- If should_reschedule is TRUE from the phase function (and no error), it will be rescheduled.

        WHEN 'finished' THEN
            RAISE DEBUG '[Job %] Already finished.', job_id;
            should_reschedule := FALSE;

        ELSE
            RAISE EXCEPTION '[Job %] Unknown import job state: %', job.id, job.state;
    END CASE;

    -- Reset the user context
    PERFORM admin.reset_import_job_user_context();

    -- Reschedule if work remains for the current phase or if transitioned to a processing state
    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
        RAISE DEBUG '[Job %] Rescheduled for further processing.', job_id;
    END IF;

EXCEPTION WHEN OTHERS THEN
    -- Ensure context is reset even on error
    PERFORM admin.reset_import_job_user_context();
    RAISE; -- Re-raise the original error
END;
$procedure$
```
