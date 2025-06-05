```sql
CREATE OR REPLACE FUNCTION admin.import_job_process_phase(job import_job, phase import_step_phase)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    batch_size INTEGER := 1000; -- Process up to 1000 rows per target step in one transaction
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    rows_processed_in_tx INTEGER := 0;
    work_still_exists_for_phase BOOLEAN := FALSE; -- Indicates if rows for this phase still exist after processing
    batch_row_ids BIGINT[]; -- Changed from TID[] to BIGINT[]
    error_message TEXT;
    current_phase_data_state public.import_data_state;
    v_sql TEXT; -- Added declaration for v_sql
BEGIN
    RAISE DEBUG '[Job %] Processing phase: %', job.id, phase;

    -- Determine the data state corresponding to the current phase
    IF phase = 'analyse'::public.import_step_phase THEN
        current_phase_data_state := 'analysing'::public.import_data_state;
    ELSIF phase = 'process'::public.import_step_phase THEN
        current_phase_data_state := 'processing'::public.import_data_state;
    ELSE
        RAISE EXCEPTION '[Job %] Invalid phase specified: %', job.id, phase;
    END IF;

    -- Load steps from the job's snapshot
    targets := job.definition_snapshot->'import_step_list';
    IF targets IS NULL OR jsonb_typeof(targets) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_step_list array from definition_snapshot', job.id;
    END IF;

    -- Loop through steps (targets) in priority order
    FOR target_rec IN SELECT * FROM jsonb_to_recordset(targets) AS x(
                            id int, code text, name text, priority int, analyse_procedure regproc, process_procedure regproc) -- Added 'code'
                      ORDER BY priority
    LOOP
        -- Determine which procedure to call for this phase
        IF phase = 'analyse'::public.import_step_phase THEN
            proc_to_call := target_rec.analyse_procedure;
        ELSE -- 'process' phase
            proc_to_call := target_rec.process_procedure;
        END IF;

        -- Skip if no procedure defined for this target/phase
        IF proc_to_call IS NULL THEN
            RAISE DEBUG '[Job %] Skipping target % (priority %) for phase % - no procedure defined.', job.id, target_rec.name, target_rec.priority, phase;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Checking target % (priority %) for phase % using procedure %', job.id, target_rec.name, target_rec.priority, phase, proc_to_call;

        -- Find one batch of rows ready for this target's phase
        EXECUTE format(
            $$SELECT array_agg(row_id) FROM (
                SELECT row_id FROM public.%I
                WHERE state = %L AND last_completed_priority < %L
                ORDER BY row_id -- Ensure consistent batching using row_id
                LIMIT %L
                FOR UPDATE SKIP LOCKED -- Avoid waiting for locked rows
             ) AS batch$$,
            job.data_table_name,
            current_phase_data_state,
            target_rec.priority,
            batch_size
        ) INTO batch_row_ids;

        -- If no rows found for this target, move to the next target
        IF batch_row_ids IS NULL OR array_length(batch_row_ids, 1) = 0 THEN
            RAISE DEBUG '[Job %] No rows found for target % (priority %) in state % with priority < %.',
                        job.id, target_rec.name, target_rec.priority,
                        current_phase_data_state, target_rec.priority;
            CONTINUE; -- Move to the next target in the FOR loop
        END IF;

        RAISE DEBUG '[Job %] Found batch of % rows for target % (priority %), calling %',
                    job.id, array_length(batch_row_ids, 1), target_rec.name, target_rec.priority, proc_to_call;

        -- Call the target-specific procedure
        BEGIN
            -- Always pass the step_code as the third argument
            EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, batch_row_ids, target_rec.code;
            rows_processed_in_tx := rows_processed_in_tx + array_length(batch_row_ids, 1);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Programming error suspected in procedure % for target % (code: %): %', job.id, proc_to_call, target_rec.name, target_rec.code, error_message;
            -- Log the job error before re-raising
            UPDATE public.import_job SET error = jsonb_build_object('programming_error_in_step_procedure', format('Error during %s phase, target %s (code: %s, proc: %s): %s', phase, target_rec.name, target_rec.code, proc_to_call::text, error_message))
            WHERE id = job.id;
            RAISE; -- Re-raise the original exception to halt and indicate a programming error
        END;
        -- After processing one batch for a target, continue to the next target.
        -- The function will determine if overall work remains for the phase at the end.
    END LOOP; -- End target loop

    -- After attempting to process one batch for all applicable targets,
    -- check if there are still any rows in the current phase's state that can be processed by any step in this phase.
    -- This determines if the calling procedure should reschedule.
    v_sql := 'SELECT EXISTS (SELECT 1 FROM public.%I dt JOIN jsonb_to_recordset(%L::JSONB) AS s(id int, code text, name text, priority int, analyse_procedure regproc, process_procedure regproc) ON TRUE WHERE dt.state = %L AND dt.last_completed_priority < s.priority AND CASE %L::public.import_step_phase WHEN ''analyse'' THEN s.analyse_procedure IS NOT NULL WHEN ''process'' THEN s.process_procedure IS NOT NULL ELSE FALSE END)';
    EXECUTE format(v_sql, job.data_table_name, job.definition_snapshot->'import_step_list', current_phase_data_state, phase)
    INTO work_still_exists_for_phase;

    RAISE DEBUG '[Job %] Phase % processing pass complete for this transaction. Rows processed in tx: %. Work still exists for phase (final check): %',
                job.id, phase, rows_processed_in_tx, work_still_exists_for_phase;

    RETURN work_still_exists_for_phase;
END;
$function$
```
