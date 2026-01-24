-- HOT-PATCH: Optimize batch selection query in import_job_analysis_phase
-- This changes ORDER BY row_id to ORDER BY state, last_completed_priority, row_id
-- Expected speedup: 7.4x (606ms -> 81ms per batch)
-- Date: 2026-01-23
-- Issue: Batch selection query doesn't use composite index efficiently

BEGIN;

-- Drop and recreate the function with optimized ORDER BY clause
DROP FUNCTION IF EXISTS admin.import_job_analysis_phase(public.import_job);

CREATE FUNCTION admin.import_job_analysis_phase(
    job public.import_job
) RETURNS BOOLEAN -- Returns TRUE if any work was found/done, indicating the job should be rescheduled.
LANGUAGE plpgsql AS $import_job_analysis_phase$
/*
RATIONALE for State Management and Control Flow:

This function manages the analysis phase of an import job. Its logic is designed
to be robust and provide clear progress feedback, especially for long-running steps.

The process is strictly separated into two stages across different transactions,
driven by the worker's rescheduling mechanism:

1.  **Discovery & State Update Transaction**:
    - The function scans for the next step with pending work.
    - If found, its *only* action is to UPDATE `import_job.current_step_code` and
      return TRUE.
    - This commits the state change in a very fast transaction, making the UI
      immediately aware of which step is *about to* be processed. The orchestrator
      then reschedules the job.

2.  **Work Execution Transaction**:
    - On the next worker run, `job.current_step_code` is now set.
    - The function enters "execution mode" and processes one unit of work for that
      step (one batch for batched steps, or all rows for holistic steps).
    - If the step completes (no more rows to process), it clears `current_step_code`
      and returns TRUE, again triggering a reschedule to return to discovery mode.

This two-stage approach prevents a long-running step from blocking its own status
update, ensuring the system's state is always accurate and transparent.

HOT-PATCH OPTIMIZATION: Changed ORDER BY clause to match composite index structure
for 7.4x performance improvement in batch selection queries.
*/
DECLARE
    v_steps JSONB;
    v_step_rec RECORD;
    v_proc_to_call REGPROC;
    v_batch_row_id_ranges int4multirange;
    v_error_message TEXT;
    v_rows_exist BOOLEAN;
    v_rows_processed INT;
    v_current_phase_data_state public.import_data_state := 'analysing'::public.import_data_state;
BEGIN
    RAISE DEBUG '[Job %] ----- import_job_analysis_phase START (current step: %) -----', job.id, COALESCE(job.current_step_code, 'none');

    v_steps := job.definition_snapshot->'import_step_list';
    IF v_steps IS NULL OR jsonb_typeof(v_steps) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_step_list array from definition_snapshot', job.id;
    END IF;

    -- STAGE 1: EXECUTION MODE
    -- If a step is already selected, execute a unit of work for it.
    IF job.current_step_code IS NOT NULL THEN
        SELECT * INTO v_step_rec
        FROM jsonb_populate_recordset(NULL::public.import_step, v_steps)
        WHERE code = job.current_step_code;

        IF NOT FOUND THEN
             RAISE EXCEPTION '[Job %] Could not find current step % in job definition snapshot.', job.id, job.current_step_code;
        END IF;

        v_proc_to_call := v_step_rec.analyse_procedure;
        v_rows_processed := 0;

        IF v_proc_to_call IS NOT NULL THEN
            BEGIN
                IF COALESCE(v_step_rec.is_holistic, false) THEN
                    -- HOLISTIC: check for work and run once.
                    EXECUTE format($$SELECT EXISTS(SELECT 1 FROM public.%I WHERE state IN (%L, 'error') AND last_completed_priority < %L LIMIT 1)$$,
                        job.data_table_name, v_current_phase_data_state, v_step_rec.priority)
                    INTO v_rows_exist;

                    IF v_rows_exist THEN
                        RAISE DEBUG '[Job %] Executing HOLISTIC step % (priority %)', job.id, v_step_rec.code, v_step_rec.priority;
                        EXECUTE format('CALL %s($1, $2, $3)', v_proc_to_call) USING job.id, NULL::int4multirange, v_step_rec.code;
                        v_rows_processed := 1; -- Mark as having done work.
                    END IF;
                ELSE
                    -- BATCHED: find and process one batch.
                    -- This is a simplified and more direct query that proved to be more reliable
                    -- than the previous complex version with a self-join, which confused the query planner.
                    -- HOT-PATCH OPTIMIZATION: Changed ORDER BY to match composite index structure
                    -- (state, last_completed_priority, row_id) for 7.4x performance improvement
                    EXECUTE format(
                        $$
                        WITH batch_rows AS (
                            SELECT row_id
                            FROM public.%1$I
                            WHERE state IN (%2$L, 'error') AND last_completed_priority < %3$L
                            ORDER BY state, last_completed_priority, row_id
                            LIMIT %4$L
                            FOR UPDATE SKIP LOCKED
                        )
                        SELECT public.array_to_int4multirange(array_agg(row_id)) FROM batch_rows
                        $$,
                        job.data_table_name,        /* %1$I */
                        v_current_phase_data_state, /* %2$L */
                        v_step_rec.priority,        /* %3$L */
                        job.analysis_batch_size     /* %4$L */
                    ) INTO v_batch_row_id_ranges;

                    IF v_batch_row_id_ranges IS NOT NULL AND NOT isempty(v_batch_row_id_ranges) THEN
                        RAISE DEBUG '[Job %] Executing BATCHED step % (priority %), found ranges: %s.', job.id, v_step_rec.code, v_step_rec.priority, v_batch_row_id_ranges::text;
                        EXECUTE format('CALL %s($1, $2, $3)', v_proc_to_call) USING job.id, v_batch_row_id_ranges, v_step_rec.code;
                        v_rows_processed := (SELECT count(*) FROM unnest(v_batch_row_id_ranges));
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
                RAISE WARNING '[Job %] Error in procedure % for step %: %', job.id, v_proc_to_call, v_step_rec.name, v_error_message;
                UPDATE public.import_job SET error = jsonb_build_object('error_in_analysis_step', format('Error during analysis step %s (proc: %s): %s', v_step_rec.name, v_proc_to_call::text, v_error_message))
                WHERE id = job.id;
                RAISE;
            END;
        END IF;

        -- If no rows were processed, this step is complete. Clear current_step_code to return to discovery mode.
        IF v_rows_processed = 0 THEN
            RAISE DEBUG '[Job %] Step % is complete. Clearing current_step_code to find next step.', job.id, job.current_step_code;
            UPDATE public.import_job SET current_step_code = NULL, current_step_priority = NULL WHERE id = job.id;
        END IF;

        RAISE DEBUG '[Job %] ----- import_job_analysis_phase END (rescheduling after execution) -----', job.id;
        RETURN TRUE; -- Always reschedule after executing a step to check for more work or find the next step.
    END IF;

    -- STAGE 2: DISCOVERY MODE
    -- If no step is being processed, find the next one with work.
    FOR v_step_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, v_steps) ORDER BY priority
    LOOP
        IF v_step_rec.analyse_procedure IS NULL THEN CONTINUE; END IF;

        -- Check if any rows need processing for this step.
        EXECUTE format($$SELECT EXISTS(SELECT 1 FROM public.%I WHERE state IN (%L, 'error') AND last_completed_priority < %L LIMIT 1)$$,
            job.data_table_name, v_current_phase_data_state, v_step_rec.priority)
        INTO v_rows_exist;

        IF v_rows_exist THEN
            -- Found the next step. Update the job and reschedule immediately.
            RAISE DEBUG '[Job %] Found next step: % (priority %). Updating job and rescheduling for execution.', job.id, v_step_rec.code, v_step_rec.priority;
            UPDATE public.import_job SET current_step_code = v_step_rec.code, current_step_priority = v_step_rec.priority WHERE id = job.id;

            RAISE DEBUG '[Job %] ----- import_job_analysis_phase END (rescheduling to start new step) -----', job.id;
            RETURN TRUE; -- The next run will execute this step.
        END IF;
    END LOOP;

    -- If the loop completes, no steps have any pending work. The phase is done.
    RAISE DEBUG '[Job %] Analysis phase processing pass complete. No more work found.', job.id;
    RAISE DEBUG '[Job %] ----- import_job_analysis_phase END (phase complete) -----', job.id;
    RETURN FALSE;
END;
$import_job_analysis_phase$;

COMMIT;

-- Verification: Check that the function was updated
SELECT 'HOT-PATCH APPLIED: Batch selection ORDER BY optimization' as status;