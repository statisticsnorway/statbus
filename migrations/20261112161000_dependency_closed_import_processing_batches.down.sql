BEGIN;

-- The command's task foreign key preserves any recorded batch history. Rollback is available
-- before use, rather than deleting completed or active import tasks to remove their command.
DELETE FROM worker.command_registry WHERE command = 'import_job_process_batch';
DROP INDEX worker.tasks_import_job_batch_unique;

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
$function$;

COMMENT ON FUNCTION admin.import_job_processing_phase(public.import_job) IS NULL;
DROP PROCEDURE admin.import_job_process_batch_after();
DROP PROCEDURE admin.import_job_process_batch_task(jsonb, jsonb);
DROP FUNCTION admin.import_job_process_one_batch(public.import_job, integer);

CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(p_data_table_name text, p_batch_size integer, p_for_processing boolean DEFAULT false, p_new_state import_data_state DEFAULT NULL::import_data_state, p_reset_priority boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_rows INTEGER;
    v_extra_sets TEXT := '';
BEGIN
    -- Build optional SET clauses for atomic multi-column update
    IF p_new_state IS NOT NULL THEN
        v_extra_sets := v_extra_sets || format(', state = %L', p_new_state);
    END IF;
    IF p_reset_priority THEN
        v_extra_sets := v_extra_sets || ', last_completed_priority = 0';
    END IF;

    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- NULL out batch_seq for non-'use' rows. These rows should already be in 'error' state
        -- (set by analyse_external_idents when action='skip'), but we defensively ensure it here
        -- to satisfy the CHECK constraint (which requires batch_seq IS NOT NULL for 'analysing' state).
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL, state = 'error' WHERE action IS DISTINCT FROM 'use' AND state != 'error'$$, p_data_table_name);
        
        -- Re-assign batch_seq to 'use' rows, optionally updating state and priority atomically.
        EXECUTE format($$
            WITH numbered AS (
                SELECT row_id, 
                       ((row_number() OVER (ORDER BY row_id) - 1) / %2$L + 1)::INTEGER as batch_num
                FROM public.%1$I
                WHERE action = 'use'
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num %3$s
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows, optionally updating state atomically.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER %3$s
            WHERE true -- every row: the analysis phase numbers all rows
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$function$;

COMMENT ON FUNCTION admin.import_job_assign_batch_seq(text, integer, boolean, public.import_data_state, boolean) IS NULL;

CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN p_batch_seq integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
    v_should_disable_triggers BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] Processing batch_seq % through all process steps.', job.id, p_batch_seq;
    targets := job.definition_snapshot->'import_step_list';

    -- Check if the batch contains any operations that are not simple inserts.
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM public.%I dt WHERE dt.batch_seq = $1 AND dt.operation IS DISTINCT FROM %L)',
        job.data_table_name,
        'insert'
    )
    INTO v_should_disable_triggers
    USING p_batch_seq;

    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Batch contains updates/replaces. Disabling FK triggers.', job.id;
        CALL admin.disable_temporal_triggers();
    ELSE
        RAISE DEBUG '[Job %] Batch is insert-only. Skipping trigger disable/enable.', job.id;
    END IF;

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        -- Skip holistic steps — they run once after all batches, not per-batch
        IF COALESCE(target_rec.is_holistic, false) THEN
            CONTINUE;
        END IF;

        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;

        -- Since this is one transaction, any error will roll back the entire batch.
        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, p_batch_seq, target_rec.code;
    END LOOP;

    -- Re-enable triggers if they were disabled.
    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Re-enabling FK triggers.', job.id;
        CALL admin.enable_temporal_triggers();
    END IF;

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$;

COMMENT ON PROCEDURE admin.import_job_process_batch(public.import_job, integer) IS NULL;

COMMIT;
