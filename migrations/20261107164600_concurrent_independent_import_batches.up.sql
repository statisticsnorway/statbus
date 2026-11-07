BEGIN;

CREATE FUNCTION admin.import_job_process_one_batch(job public.import_job, p_batch_seq integer)
RETURNS integer
LANGUAGE plpgsql
AS $import_job_process_one_batch$
DECLARE
    v_rows_processed integer;
    error_message text;
    error_context text;
BEGIN
    -- The task uniqueness index gives each (job, batch) one scheduled leaf. This lock also makes a
    -- direct replay wait for an in-flight invocation before checking its committed row states.
    PERFORM pg_advisory_xact_lock(hashtextextended(format('import_batch:%s:%s', job.id, p_batch_seq), 0));
    EXECUTE format($SQL$
        SELECT count(*) FROM public.%1$I WHERE batch_seq = $1 AND state = 'processing'
    $SQL$, job.data_table_name) INTO v_rows_processed USING p_batch_seq;
    IF v_rows_processed = 0 THEN
        RETURN 0;
    END IF;

    BEGIN
        CALL admin.import_job_process_batch(job, p_batch_seq);
        EXECUTE format($SQL$
            UPDATE public.%1$I SET state = 'processed'
            WHERE batch_seq = $1 AND state = 'processing'
        $SQL$, job.data_table_name) USING p_batch_seq;
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
        -- Keep this atomic increment at the transaction tail so progress remains live without
        -- holding the shared job row throughout temporal_merge or its supporting queries.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;
    EXCEPTION
        WHEN deadlock_detected OR serialization_failure THEN
            RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT, error_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
                job.id, p_batch_seq, error_message, error_context;
            EXECUTE format($SQL$
                UPDATE public.%1$I
                SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || $1
                WHERE batch_seq = $2
            $SQL$, job.data_table_name)
            USING jsonb_build_object('process_batch_error', error_message, 'context', error_context), p_batch_seq;
            UPDATE public.import_job
            SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::text,
                state = 'failed'
            WHERE id = job.id;
            RETURN NULL;
    END;
    RETURN v_rows_processed;
END;
$import_job_process_one_batch$;

COMMENT ON FUNCTION admin.import_job_process_one_batch(public.import_job, integer) IS
'Processes one whole dependency batch and atomically publishes its row states and imported_rows delta. A committed batch is replay-safe, failures mark the job failed, and transaction conflicts propagate to the worker retry policy.';

CREATE PROCEDURE admin.import_job_process_batch_task(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL)
LANGUAGE plpgsql
AS $import_job_process_batch_task$
DECLARE
    v_job public.import_job;
    v_rows_processed integer;
    v_batch_seq integer := (payload->>'batch_seq')::integer;
BEGIN
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = (payload->>'job_id')::integer;
    IF v_batch_seq IS NULL OR v_batch_seq < 1 THEN
        RAISE EXCEPTION 'A positive import processing batch_seq is required';
    END IF;
    PERFORM admin.set_import_job_user_context(v_job.id);
    IF v_job.state <> 'processing_data' THEN
        p_info := jsonb_build_object('job_state', v_job.state::text);
        RETURN;
    END IF;
    v_rows_processed := admin.import_job_process_one_batch(v_job, v_batch_seq);
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = v_job.id;
    IF v_rows_processed IS NULL OR v_job.state = 'failed' THEN
        -- The worker records a failed leaf after rolling back this handler. Its after_procedure
        -- publishes the job failure outside that savepoint so parent fan-in also remains failed.
        RAISE EXCEPTION USING MESSAGE = COALESCE(v_job.error, 'Import processing batch failed');
    END IF;
    p_info := jsonb_build_object('batch_rows_imported', v_rows_processed);
END;
$import_job_process_batch_task$;

COMMENT ON PROCEDURE admin.import_job_process_batch_task(jsonb, jsonb) IS
'Worker leaf for an analysed import job processing batch. It restores the import owner context, processes only its payload batch, and leaves holistic steps and job finalization to the serial continuation after fan-in.';

CREATE PROCEDURE admin.import_job_process_batch_after()
LANGUAGE plpgsql
AS $import_job_process_batch_after$
DECLARE
    v_task worker.tasks;
    v_job public.import_job;
    v_error jsonb;
BEGIN
    -- The worker calls this after publishing its task result. Completion time identifies the
    -- invocation just handled, including when older queued task IDs execute after newer ones.
    SELECT * INTO v_task FROM worker.tasks
    WHERE command = 'import_job_process_batch' AND worker_pid = pg_backend_pid()
    ORDER BY process_stop_at DESC NULLS LAST, id DESC LIMIT 1;
    IF NOT FOUND OR v_task.state <> 'failed' THEN
        RETURN;
    END IF;
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = (v_task.payload->>'job_id')::integer;
    PERFORM admin.set_import_job_user_context(v_job.id);
    v_error := jsonb_build_object('processing_task_failed', v_task.id, 'error', v_task.error);
    EXECUTE format($SQL$
        UPDATE public.%1$I
        SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || $1
        WHERE batch_seq = $2 AND state = 'processing'
    $SQL$, v_job.data_table_name)
    USING v_error, (v_task.payload->>'batch_seq')::integer;
    UPDATE public.import_job
    SET state = 'failed', error = COALESCE(error, v_error::text)
    WHERE id = v_job.id AND (state <> 'failed' OR error IS NULL);
END;
$import_job_process_batch_after$;

COMMENT ON PROCEDURE admin.import_job_process_batch_after() IS
'Publishes failed processing leaf diagnostics to its import job and batch rows after the worker has rolled back the handler. This preserves atomic batch rollback and failed parent fan-in while retaining the first recorded job error.';

INSERT INTO worker.command_registry(command, handler_procedure, after_procedure, description, queue)
VALUES ('import_job_process_batch', 'admin.import_job_process_batch_task',
        'admin.import_job_process_batch_after',
        'Process one independent import batch under its job processing barrier', 'import');

CREATE UNIQUE INDEX tasks_import_job_batch_unique
ON worker.tasks ((payload->>'job_id'), (payload->>'batch_seq'))
WHERE command = 'import_job_process_batch';
COMMENT ON INDEX worker.tasks_import_job_batch_unique IS
'One scheduled task per analysed job batch, including its interrupted retry lifecycle. Batch identities stay fixed for the lifetime of an import job.';

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
    v_task_id bigint;
    v_batch record;
    v_can_dispatch boolean;
    v_unit_condition text;
    v_failed_task worker.tasks;
BEGIN
    -- A leaf failure outside the batch handler, including an exhausted transaction retry, must
    -- become a failed import rather than silently redispatching or proceeding to holistic steps.
    SELECT * INTO v_failed_task FROM worker.tasks
    WHERE command = 'import_job_process_batch' AND payload->>'job_id' = job.id::text AND state = 'failed'
    ORDER BY id LIMIT 1;
    IF FOUND THEN
        UPDATE public.import_job
        SET state = 'failed', error = jsonb_build_object('processing_task_failed', v_failed_task.id,
                                                       'error', v_failed_task.error)::text
        WHERE id = job.id;
        RETURN false;
    END IF;

    EXECUTE format($$
        SELECT MIN(batch_seq), MAX(batch_seq)
        FROM public.%1$I
        WHERE batch_seq IS NOT NULL AND state = 'processing'
    $$, job.data_table_name) INTO v_current_batch, v_max_batch;

    IF v_current_batch IS NOT NULL THEN
        SELECT id INTO v_task_id FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
          AND command = 'import_job_process' AND payload->>'job_id' = job.id::text
        ORDER BY id DESC LIMIT 1;

        -- Initial concurrency scope: new legal units with new enterprises, or new formal
        -- establishments. Existing-unit and mixed jobs retain the serial path until temporal
        -- checks can be deferred without table-locking trigger DDL. Unknown batch handlers also
        -- retain their serial contract. Holistic handlers remain behind this task's fan-in barrier.
        IF v_task_id IS NOT NULL AND v_current_batch <> v_max_batch AND COALESCE(job.imported_rows, 0) = 0
           AND job.definition_snapshot#>>'{import_definition,mode}' IN ('legal_unit', 'establishment_formal')
           AND NOT EXISTS (
               SELECT 1 FROM jsonb_populate_recordset(NULL::public.import_step,
                                                      job.definition_snapshot->'import_step_list') AS step
               WHERE NOT COALESCE(step.is_holistic, false) AND step.process_procedure IS NOT NULL
                 AND step.process_procedure::text NOT IN (
                     'import.process_enterprise_link_for_legal_unit', 'import.process_legal_unit',
                     'import.process_establishment', 'import.process_location', 'import.process_activity',
                     'import.process_contact', 'import.process_statistical_variables', 'import.process_tags')
           ) THEN
            v_unit_condition := CASE job.definition_snapshot#>>'{import_definition,mode}'
                WHEN 'legal_unit' THEN 'legal_unit_id IS NULL AND enterprise_id IS NULL'
                WHEN 'establishment_formal' THEN 'establishment_id IS NULL AND legal_unit_id IS NOT NULL'
            END;
            EXECUTE format($SQL$
                SELECT bool_and(operation = 'insert' AND founding_row_id IS NOT NULL AND (%2$s))
                       AND NOT EXISTS (
                           SELECT founding_row_id FROM public.%1$I
                           WHERE state = 'processing'
                           GROUP BY founding_row_id HAVING count(DISTINCT batch_seq) > 1
                       )
                FROM public.%1$I WHERE state = 'processing'
            $SQL$, job.data_table_name, v_unit_condition) INTO v_can_dispatch;
            IF v_can_dispatch THEN
                FOR v_batch IN EXECUTE format($SQL$
                    SELECT DISTINCT batch_seq FROM public.%1$I
                    WHERE state = 'processing' AND batch_seq IS NOT NULL ORDER BY batch_seq
                $SQL$, job.data_table_name)
                LOOP
                    PERFORM worker.spawn(
                        p_command => 'import_job_process_batch',
                        p_payload => jsonb_build_object('job_id', job.id, 'batch_seq', v_batch.batch_seq),
                        p_parent_id => v_task_id,
                        p_child_mode => 'concurrent');
                END LOOP;
                RETURN true;
            END IF;
        END IF;

        v_rows_processed := admin.import_job_process_one_batch(job, v_current_batch);
        RETURN v_rows_processed IS NOT NULL;
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

COMMENT ON FUNCTION admin.import_job_processing_phase(public.import_job) IS
'Dispatches dependency-closed batches of new insert-only legal units or formal establishments through concurrent worker children. Mixed or existing-unit jobs use serial batches. Holistic steps and finalization resume only after the child barrier, and failed leaves fail the job.';

COMMIT;
