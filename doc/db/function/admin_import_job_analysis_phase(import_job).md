```sql
CREATE OR REPLACE FUNCTION admin.import_job_analysis_phase(job import_job)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
/*
RATIONALE for Holistic vs. Batched Steps and Transaction Model:

This function is the core of the step-by-step processing logic. It is designed to be called repeatedly by the worker system. Each call executes ONE unit of work in a single transaction and then exits.

1.  **Single Worker Model**: The user has clarified that the worker system runs a single worker per queue. This means there is no parallel execution of this function for the *same job*. The primary purpose of batching is therefore not for concurrency control, but to keep transactions small, responsive, and to provide granular progress feedback.

2.  **`is_holistic` Flag's Purpose**: The flag is NOT for preventing race conditions (as the queue model already does that). It is for ensuring DATA COMPLETENESS. Certain analysis steps (e.g., finding a `founding_row_id` for a new entity) must see the entire dataset to make a correct decision. A batched procedure, by design, only sees a small slice of the data and cannot perform these calculations correctly.
    - `is_holistic = true`: The procedure is called once for the entire phase. It is responsible for loading all relevant rows itself.
    - `is_holistic = false`: The procedure is called repeatedly, once for each batch of rows.

3.  **"Run Once" Guarantee for Holistic Steps**: A holistic step is guaranteed to run only once per phase because:
    a. It is only selected if there are rows with `last_completed_priority < step.priority`.
    b. The procedure itself updates the `last_completed_priority` for ALL rows it processes in a single transaction.
    c. The function then returns `TRUE`, forcing a reschedule.
    d. On the next run, the condition in (a) is no longer met for this step, so the processor moves to the next step.

4.  **`RETURN TRUE` vs `RETURN FALSE`**:
    - `RETURN TRUE`: "Work was found and processed in this transaction." The calling procedure (`admin.import_job_process`) will immediately reschedule the job.
    - `RETURN FALSE`: "A full loop over all steps for this phase found no work." This signals that the phase is complete, and the job can transition to its next state.
*/
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    rows_processed_in_tx INTEGER := 0;
    any_work_found_in_tx BOOLEAN := FALSE; -- If we find any batch, we should reschedule.
    batch_row_ids INTEGER[];
    error_message TEXT;
    current_phase_data_state public.import_data_state := 'analysing'::public.import_data_state;
BEGIN
    RAISE DEBUG '[Job %] Processing analysis phase.', job.id;

    -- Load steps from the job's snapshot
    targets := job.definition_snapshot->'import_step_list';
    IF targets IS NULL OR jsonb_typeof(targets) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_step_list array from definition_snapshot', job.id;
    END IF;

    -- Loop through steps (targets) in priority order
    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets)
                      ORDER BY priority
    LOOP
        proc_to_call := target_rec.analyse_procedure;

        -- Skip if no procedure defined for this target/phase
        IF proc_to_call IS NULL THEN
            RAISE DEBUG '[Job %] Skipping target % (priority %) for analysis phase - no procedure defined.', job.id, target_rec.name, target_rec.priority;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Checking target % (priority %) for analysis phase using procedure % (is_holistic: %)',
            job.id, target_rec.name, target_rec.priority, proc_to_call, target_rec.is_holistic;

        -- Update the job record to reflect the current step being processed *before* executing it.
        -- This provides real-time monitoring of which step the job is currently working on.
        UPDATE public.import_job SET current_step_code = target_rec.code, current_step_priority = target_rec.priority WHERE id = job.id;

        -- Handle holistic vs. batched steps
        BEGIN
            IF COALESCE(target_rec.is_holistic, false) THEN
                -- HOLISTIC STEP: Called once per phase. Processes all relevant rows.
                DECLARE v_rows_exist BOOLEAN;
                BEGIN
                    EXECUTE format($$SELECT EXISTS(SELECT 1 FROM public.%I WHERE state = %L AND last_completed_priority < %L LIMIT 1)$$,
                        job.data_table_name, current_phase_data_state, target_rec.priority)
                    INTO v_rows_exist;

                    IF v_rows_exist THEN
                        RAISE DEBUG '[Job %] Calling holistic procedure % for target %.', job.id, proc_to_call, target_rec.name;
                        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, NULL::INTEGER[], target_rec.code;
                        -- The holistic procedure itself must update last_completed_priority.
                        -- Since work was found and done, return immediately to reschedule.
                        RETURN TRUE;
                    END IF;
                END;
            ELSE
                -- BATCHED STEP: Called repeatedly. Processes one batch at a time.
                EXECUTE format(
                    $$SELECT array_agg(row_id) FROM (
                        SELECT row_id FROM public.%I
                        WHERE state = %L AND last_completed_priority < %L
                        ORDER BY row_id LIMIT %L FOR UPDATE SKIP LOCKED
                     ) AS batch$$,
                    job.data_table_name, current_phase_data_state, target_rec.priority, job.analysis_batch_size
                ) INTO batch_row_ids;

                IF batch_row_ids IS NOT NULL AND array_length(batch_row_ids, 1) > 0 THEN
                    RAISE DEBUG '[Job %] Found batch of % rows for target % (priority %), calling %',
                        job.id, array_length(batch_row_ids, 1), target_rec.name, target_rec.priority, proc_to_call;

                    EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, batch_row_ids, target_rec.code;

                    -- Since work was found and done, return immediately to reschedule.
                    RETURN TRUE;
                END IF;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Programming error suspected in procedure % for target % (code: %): %', job.id, proc_to_call, target_rec.name, target_rec.code, error_message;
            UPDATE public.import_job SET error = jsonb_build_object('programming_error_in_step_procedure', format('Error during analysis phase, target %s (code: %s, proc: %s): %s', target_rec.name, target_rec.code, proc_to_call::text, error_message))
            WHERE id = job.id;
            RAISE;
        END;
    END LOOP; -- End target loop

    -- If the loop completes, it means a full pass over all steps found no pending work.
    -- The phase is therefore complete. Return false to stop rescheduling.
    RAISE DEBUG '[Job %] Analysis phase processing pass complete. No work found.', job.id;
    RETURN FALSE;
END;
$function$
```
