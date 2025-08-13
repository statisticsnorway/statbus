```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer)
 LANGUAGE plpgsql
AS $procedure$
/*
RATIONALE for Control Flow:

This procedure acts as the main "Orchestrator" for a single import job. It is called by the worker system.
Its primary responsibilities are:
1.  Managing the high-level STATE of the import job (e.g., from 'analysing_data' to 'waiting_for_review').
2.  Calling the "Phase Processor" (`admin.import_job_process_phase`) to perform the actual work for a given state.
3.  Interpreting the boolean return value from the Phase Processor to decide on the next action.

The `should_reschedule` variable is key. It holds the return value from `import_job_process_phase`.
- `TRUE`:  Indicates that one unit of work was completed, but the phase is not finished. The Orchestrator MUST reschedule itself to continue processing in the CURRENT state.
- `FALSE`: Indicates that a full pass over all steps in the phase found no work left to do. The Orchestrator MUST transition the job to the NEXT state.
*/
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
            DECLARE
                v_data_row_count BIGINT;
            BEGIN
                RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
                PERFORM admin.import_job_prepare(job);

                -- After preparing, recount total_rows from the data table as UPSERT might have changed the count.
                -- Also, recalculate total_analysis_steps_weighted with the correct row count.
                EXECUTE format('SELECT COUNT(*) FROM public.%I', job.data_table_name) INTO v_data_row_count;

                UPDATE public.import_job
                SET
                    total_rows = v_data_row_count,
                    total_analysis_steps_weighted = v_data_row_count * max_analysis_priority
                WHERE id = job.id
                RETURNING * INTO job; -- Refresh local job variable to have updated values.

                RAISE DEBUG '[Job %] Recounted total_rows to % and updated total_analysis_steps_weighted.', job.id, job.total_rows;

                -- Transition rows in _data table from 'pending' to 'analysing'
                RAISE DEBUG '[Job %] Updating data rows from pending to analysing in table %', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysing'::public.import_data_state, 'pending'::public.import_data_state);
                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start analysis
            END;

        WHEN 'analysing_data' THEN
            DECLARE
                v_completed_steps_weighted BIGINT;
            BEGIN
                RAISE DEBUG '[Job %] Starting analysis phase.', job_id;

                should_reschedule := admin.import_job_analysis_phase(job);

                -- After each batch run, recount progress. State transitions happen only when the phase is complete.
                IF job.max_analysis_priority IS NOT NULL THEN
                    -- Recount weighted steps for granular progress
                    EXECUTE format($$ SELECT COALESCE(SUM(last_completed_priority), 0) FROM public.%I WHERE state IN ('analysing', 'analysed', 'error') $$,
                        job.data_table_name)
                    INTO v_completed_steps_weighted;

                    UPDATE public.import_job
                    SET completed_analysis_steps_weighted = v_completed_steps_weighted
                    WHERE id = job.id;

                    RAISE DEBUG '[Job %] Recounted progress: completed_analysis_steps_weighted=%', job.id, v_completed_steps_weighted;
                END IF;

                -- Refresh job record to see if an error was set by the phase
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during analysis phase: %. Transitioning to finished.', job_id, job.error;
                    job := admin.import_job_set_state(job, 'finished');
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                    IF job.review THEN
                        -- Transition rows from 'analysing' to 'analysed' if review is required
                        -- Rows in 'analysing' state here have completed all analysis steps.
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
            END;

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            BEGIN
                RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
                -- Transition rows in _data table from 'analysed' to 'processing' and reset LCP
                RAISE DEBUG '[Job %] Updating data rows from analysed to processing and resetting LCP in table % after approval', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L AND error IS NULL$$, job.data_table_name, 'processing'::public.import_data_state, 'analysed'::public.import_data_state);
                job := admin.import_job_set_state(job, 'processing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start import
            END;

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            DECLARE
                v_processed_count INTEGER;
            BEGIN
                RAISE DEBUG '[Job %] Starting processing phase.', job_id;

                should_reschedule := admin.import_job_processing_phase(job);

                -- Recount progress after each batch.
                EXECUTE format($$SELECT count(*) FROM public.%I WHERE state = 'processed'$$, job.data_table_name)
                INTO v_processed_count;
                UPDATE public.import_job SET imported_rows = v_processed_count WHERE id = job.id;
                RAISE DEBUG '[Job %] Recounted imported_rows: %', job.id, v_processed_count;

                -- Refresh job record to see if an error was set by the phase
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during processing phase: %. Job already transitioned to finished.', job.id, job.error;
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                    job := admin.import_job_set_state(job, 'finished');
                    RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
                    -- should_reschedule remains FALSE
                END IF;
            END;

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
