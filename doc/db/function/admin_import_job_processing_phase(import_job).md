```sql
CREATE OR REPLACE FUNCTION admin.import_job_processing_phase(job import_job)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_batch INTEGER;
    v_max_batch INTEGER;
    v_rows_processed INTEGER;
    error_message TEXT;
    error_context TEXT;
    v_holistic_step RECORD;
    v_proc_to_call REGPROC;
    v_targets JSONB;
BEGIN
    -- Get the current batch to process (smallest batch_seq that still has unprocessed rows)
    EXECUTE format($$
        SELECT MIN(batch_seq), MAX(batch_seq)
        FROM public.%1$I
        WHERE batch_seq IS NOT NULL AND state = 'processing'
    $$, job.data_table_name) INTO v_current_batch, v_max_batch;

    IF v_current_batch IS NOT NULL THEN
        RAISE DEBUG '[Job %] Processing batch % of % (max).', job.id, v_current_batch, v_max_batch;

        BEGIN
            CALL admin.import_job_process_batch(job, v_current_batch);

            -- Mark all rows in the batch that are not in an error state as 'processed'.
            EXECUTE format($$
                UPDATE public.%1$I
                SET state = 'processed'
                WHERE batch_seq = %2$L AND state != 'error'
            $$, job.data_table_name, v_current_batch);
            GET DIAGNOSTICS v_rows_processed = ROW_COUNT;

            RAISE DEBUG '[Job %] Batch % successfully processed. Marked % non-error rows as processed.',
                job.id, v_current_batch, v_rows_processed;

            -- Increment imported_rows counter directly instead of doing a full table scan.
            UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                                  error_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
                job.id, v_current_batch, error_message, error_context;

            EXECUTE format($$
                UPDATE public.%1$I
                SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || %2$L
                WHERE batch_seq = %3$L
            $$, job.data_table_name,
                jsonb_build_object('process_batch_error', error_message, 'context', error_context),
                v_current_batch);

            UPDATE public.import_job
            SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::TEXT,
                state = 'failed'
            WHERE id = job.id;

            RETURN FALSE; -- On error, do not reschedule.
        END;

        RETURN TRUE; -- Batch work was done.
    END IF;

    -- All batches done. Now run holistic process steps (if any).
    -- Two-stage pattern: discovery then execution (same as analysis phase).

    -- Stage 1: Discovery — find next holistic process step that has work
    v_targets := job.definition_snapshot->'import_step_list';

    -- Check if we have a current holistic step in progress (via current_step_code)
    IF job.current_step_code IS NOT NULL THEN
        -- Stage 2: Execution — run the holistic step
        SELECT * INTO v_holistic_step
        FROM jsonb_populate_recordset(NULL::public.import_step, v_targets)
        WHERE code = job.current_step_code;

        IF FOUND AND v_holistic_step.process_procedure IS NOT NULL THEN
            RAISE DEBUG '[Job %] Executing holistic process step: %', job.id, v_holistic_step.code;

            BEGIN
                v_proc_to_call := v_holistic_step.process_procedure;
                -- Holistic steps receive NULL batch_seq
                EXECUTE format('CALL %s($1, $2, $3)', v_proc_to_call) USING job.id, NULL::integer, v_holistic_step.code;
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                                      error_context = PG_EXCEPTION_CONTEXT;
                RAISE WARNING '[Job %] Error in holistic process step %: %. Context: %.',
                    job.id, v_holistic_step.code, error_message, error_context;
                UPDATE public.import_job
                SET error = jsonb_build_object('error_in_holistic_process', error_message, 'step', v_holistic_step.code, 'context', error_context)::TEXT,
                    state = 'failed'
                WHERE id = job.id;
                RETURN FALSE;
            END;
        END IF;

        -- Clear current step code but KEEP current_step_priority so next discovery
        -- starts after this step's priority (prevents infinite re-discovery loop).
        UPDATE public.import_job
        SET current_step_code = NULL
        WHERE id = job.id;
        RETURN TRUE;
    END IF;

    -- Stage 1: Find the next holistic process step (by priority)
    SELECT * INTO v_holistic_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_targets)
    WHERE COALESCE(is_holistic, false) = true
      AND process_procedure IS NOT NULL
      AND priority > COALESCE(job.current_step_priority, 0)
    ORDER BY priority
    LIMIT 1;

    IF FOUND THEN
        -- Set current step, return TRUE (commit fast, then execute next turn)
        UPDATE public.import_job
        SET current_step_code = v_holistic_step.code,
            current_step_priority = v_holistic_step.priority
        WHERE id = job.id;
        RAISE DEBUG '[Job %] Discovered holistic process step: % (priority %)', job.id, v_holistic_step.code, v_holistic_step.priority;
        RETURN TRUE;
    END IF;

    -- No more holistic steps. Processing phase complete.
    -- Clear priority tracker so it's fresh for next job.
    UPDATE public.import_job
    SET current_step_priority = NULL
    WHERE id = job.id;
    RAISE DEBUG '[Job %] No more batches or holistic steps. Phase complete.', job.id;
    RETURN FALSE;
END;
$function$
```
