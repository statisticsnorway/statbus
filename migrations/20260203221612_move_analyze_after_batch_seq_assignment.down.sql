-- Down Migration 20260203221612: move_analyze_after_batch_seq_assignment
BEGIN;

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

                -- PERFORMANCE FIX: Analyze the data table after populating it to ensure the query planner has statistics for the analysis phase.
                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                -- ATOMICALLY assign batch_seq AND set state to 'analysing' to satisfy CHECK constraint.
                -- The constraint requires: state='analysing' implies batch_seq IS NOT NULL.
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to analysing in table %', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.analysis_batch_size, FALSE, 'analysing'::public.import_data_state);
                
                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start analysis
            END;

        WHEN 'analysing_data' THEN
            DECLARE
                v_completed_steps_weighted BIGINT;
                v_old_step_code TEXT;
            BEGIN
                RAISE DEBUG '[Job %] Starting analysis phase.', job_id;

                v_old_step_code := job.current_step_code;

                should_reschedule := admin.import_job_analysis_phase(job);

                -- Refresh job record to see current step
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                -- PERFORMANCE FIX: Only recount weighted progress when step changes (not every batch).
                -- This avoids O(n) full table scans after every batch. Instead, we only recount
                -- when moving to a new step or when the phase completes, reducing scans from ~350 to ~10.
                IF job.max_analysis_priority IS NOT NULL AND (
                    job.current_step_code IS DISTINCT FROM v_old_step_code  -- Step changed
                    OR NOT should_reschedule  -- Phase is complete
                ) THEN
                    -- Recount weighted steps for granular progress
                    EXECUTE format($$ SELECT COALESCE(SUM(last_completed_priority), 0) FROM public.%I WHERE state IN ('analysing', 'analysed', 'error') $$,
                        job.data_table_name)
                    INTO v_completed_steps_weighted;

                    UPDATE public.import_job
                    SET completed_analysis_steps_weighted = v_completed_steps_weighted
                    WHERE id = job.id;

                    RAISE DEBUG '[Job %] Recounted progress (step changed or phase complete): completed_analysis_steps_weighted=%', job.id, v_completed_steps_weighted;
                END IF;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during analysis phase: %. Transitioning to finished.', job_id, job.error;
                    job := admin.import_job_set_state(job, 'finished');
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                    IF job.review THEN
                        -- Transition rows from 'analysing' to 'analysed' if review is required
                        RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                        EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND action = 'use'$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                        job := admin.import_job_set_state(job, 'waiting_for_review');
                        RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    ELSE
                        -- ATOMICALLY assign batch_seq, set state to 'processing', AND reset priority in ONE UPDATE.
                        -- This satisfies the CHECK constraint and minimizes UPDATE count for performance.
                        RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table %', job_id, job.data_table_name;
                        PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                        -- The performance index is now created when the job is generated.
                        -- We still need to ANALYZE to update statistics after the analysis phase.
                        RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                        EXECUTE format('ANALYZE public.%I', job.data_table_name);

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
                -- ATOMICALLY assign batch_seq, set state to 'processing', AND reset priority in ONE UPDATE.
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table % after approval', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                -- The performance index is now created when the job is generated.
                -- We still need to ANALYZE to update statistics after the analysis phase.
                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'processing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start import
            END;

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            BEGIN
                RAISE DEBUG '[Job %] Starting processing phase.', job_id;

                should_reschedule := admin.import_job_processing_phase(job);

                -- PERFORMANCE FIX: Progress tracking is now done incrementally inside import_job_processing_phase.
                -- This avoids a full table scan (COUNT(*) WHERE state = 'processed') after every batch.

                -- Refresh job record to see if an error was set by the phase
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                RAISE DEBUG '[Job %] Processing phase batch complete. imported_rows: %', job.id, job.imported_rows;

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

        WHEN 'failed' THEN
            RAISE DEBUG '[Job %] Job has failed.', job_id;
            should_reschedule := FALSE;

        ELSE
            RAISE EXCEPTION 'Unexpected job state: %', job.state;
    END CASE;

    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
    END IF;
END;
$procedure$;

END;
