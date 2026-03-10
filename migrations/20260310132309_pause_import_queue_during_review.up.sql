-- Migration 20260310132309: pause_import_queue_during_review
--
-- When a job enters 'waiting_for_review', the import queue should pause
-- all other jobs until the review is resolved. This prevents dependent jobs
-- (e.g., ES that depends on LU data) from processing before their
-- prerequisite job is reviewed and approved.
--
-- Design: No polling. Blocked jobs simply don't reschedule. When a review
-- resolves (approve or reject), the after-trigger enqueues all blocked jobs.
BEGIN;

CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer)
 LANGUAGE plpgsql
AS $import_job_process$
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

    -- Block import queue while any OTHER job is waiting for review.
    -- This prevents dependent jobs (e.g., ES) from processing before their
    -- prerequisite (e.g., LU) has been reviewed and approved/rejected.
    -- Jobs that ARE in waiting_for_review/approved/rejected are exempt —
    -- they need to proceed through their own state transitions.
    -- When the review resolves, the after-trigger re-enqueues all blocked jobs.
    IF job.state NOT IN ('waiting_for_review', 'approved', 'rejected') THEN
        PERFORM id FROM public.import_job
        WHERE state = 'waiting_for_review'
          AND id <> job_id
        LIMIT 1;
        IF FOUND THEN
            RAISE DEBUG '[Job %] Blocked: another job is waiting_for_review. Will resume when review resolves.', job_id;
            -- Do NOT reschedule — the after-trigger on review resolution will re-enqueue us.
            RETURN;
        END IF;
    END IF;

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

                -- ATOMICALLY assign batch_seq AND set state to 'analysing' to satisfy CHECK constraint.
                -- The constraint requires: state='analysing' implies batch_seq IS NOT NULL.
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to analysing in table %', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.analysis_batch_size, FALSE, 'analysing'::public.import_data_state);

                -- PERFORMANCE FIX: ANALYZE must run AFTER batch_seq is assigned.
                -- Otherwise the planner sees batch_seq = NULL for all rows and estimates
                -- rows=1 for WHERE batch_seq = $1, causing Nested Loop instead of Hash Join.
                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start analysis
            END;

        WHEN 'analysing_data' THEN
            DECLARE
                v_completed_steps_weighted BIGINT;
                v_old_step_code TEXT;
                v_error_count INTEGER;
                v_warning_count INTEGER;
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
                    -- Compute error and warning counts now that analysis is complete.
                    -- This is the single point where all rows have their final analysis state.
                    EXECUTE format($$
                      SELECT
                        COUNT(*) FILTER (WHERE state = 'error'),
                        COUNT(*) FILTER (WHERE action = 'use' AND invalid_codes IS NOT NULL AND invalid_codes <> '{}'::jsonb)
                      FROM public.%I
                    $$, job.data_table_name) INTO v_error_count, v_warning_count;

                    UPDATE public.import_job
                    SET error_count = v_error_count, warning_count = v_warning_count
                    WHERE id = job.id;

                    RAISE DEBUG '[Job %] Analysis complete. error_count=%, warning_count=%', job.id, v_error_count, v_warning_count;

                    -- Tri-state review logic:
                    --   TRUE  = always review
                    --   NULL  = review only if errors found during analysis
                    --   FALSE = never review (auto-approve)
                    IF job.review IS TRUE
                       OR (job.review IS NULL AND v_error_count > 0)
                    THEN
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
$import_job_process$;


-- Update the after-trigger to also handle review resolution:
-- When a job leaves waiting_for_review (approved OR rejected), re-enqueue
-- all other jobs that are in processing-eligible states. These jobs were
-- blocked and need to resume.
CREATE OR REPLACE FUNCTION admin.import_job_state_change_after()
RETURNS TRIGGER LANGUAGE plpgsql AS $import_job_state_change_after$
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
$import_job_state_change_after$;

END;
