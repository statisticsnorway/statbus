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
        -- establishments. Existing-unit and mixed dependency coverage remains outside this scope,
        -- so those jobs retain serial processing. Supported batch handlers are matched by routine
        -- identity independently of caller search_path. Unknown handlers keep their serial contract,
        -- and holistic handlers remain behind this task's fan-in barrier.
        IF v_task_id IS NOT NULL AND v_current_batch <> v_max_batch AND COALESCE(job.imported_rows, 0) = 0
           AND job.definition_snapshot#>>'{import_definition,mode}' IN ('legal_unit', 'establishment_formal')
           AND NOT EXISTS (
               SELECT 1 FROM jsonb_populate_recordset(NULL::public.import_step,
                                                      job.definition_snapshot->'import_step_list') AS step
               WHERE NOT COALESCE(step.is_holistic, false) AND step.process_procedure IS NOT NULL
                 AND step.process_procedure NOT IN (
                     'import.process_enterprise_link_for_legal_unit'::regproc, 'import.process_legal_unit'::regproc,
                     'import.process_establishment'::regproc, 'import.process_location'::regproc, 'import.process_activity'::regproc,
                     'import.process_contact'::regproc, 'import.process_statistical_variables'::regproc, 'import.process_tags'::regproc)
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
$function$
```
