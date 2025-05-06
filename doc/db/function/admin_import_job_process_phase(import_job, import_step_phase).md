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
    batch_ctids TID[];
    error_message TEXT;
    current_phase_data_state public.import_data_state;
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
                            id int, name text, priority int, analyse_procedure regproc, process_procedure regproc)
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
            'SELECT array_agg(ctid) FROM (
                SELECT ctid FROM public.%I
                WHERE state = %L AND last_completed_priority < %L
                ORDER BY ctid -- Ensure consistent batching
                LIMIT %L
                FOR UPDATE SKIP LOCKED -- Avoid waiting for locked rows
             ) AS batch',
            job.data_table_name,
            current_phase_data_state,
            target_rec.priority,
            batch_size
        ) INTO batch_ctids;

        -- If no rows found for this target, move to the next target
        IF batch_ctids IS NULL OR array_length(batch_ctids, 1) = 0 THEN
            RAISE DEBUG '[Job %] No rows found for target % (priority %) in state % with priority < %.',
                        job.id, target_rec.name, target_rec.priority,
                        current_phase_data_state, target_rec.priority;
            CONTINUE; -- Move to the next target in the FOR loop
        END IF;

        RAISE DEBUG '[Job %] Found batch of % rows for target % (priority %), calling %',
                    job.id, array_length(batch_ctids, 1), target_rec.name, target_rec.priority, proc_to_call;

        -- Call the target-specific procedure
        BEGIN
            EXECUTE format('CALL %s($1, $2)', proc_to_call) USING job.id, batch_ctids;
            rows_processed_in_tx := rows_processed_in_tx + array_length(batch_ctids, 1);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] Error calling procedure % for target %: %', job.id, proc_to_call, target_rec.name, error_message;
            -- Mark batch rows as error
            EXECUTE format('UPDATE public.%I SET state = %L, error = %L WHERE ctid = ANY(%L)',
                           job.data_table_name, 'error'::public.import_data_state, jsonb_build_object('target_step_error', format('Target %s (%s): %s', target_rec.name, proc_to_call::text, error_message)), batch_ctids);
            -- Log the job error
            UPDATE public.import_job SET error = jsonb_build_object('phase_target_error', format('Error during %s phase, target %s (%s): %s', phase, target_rec.name, proc_to_call::text, error_message))
            WHERE id = job.id;
            -- If a step fails, stop processing this phase for this job and signal no reschedule for this phase.
            RETURN FALSE;
        END;
        -- After processing one batch for a target, continue to the next target.
        -- The function will determine if overall work remains for the phase at the end.
    END LOOP; -- End target loop

    -- After attempting to process one batch for all applicable targets,
    -- check if there are still any rows in the initial state for this phase.
    -- This determines if the calling procedure should reschedule.
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE state = %L)',
                   job.data_table_name,
                   current_phase_data_state
    ) INTO work_still_exists_for_phase;

    RAISE DEBUG '[Job %] Phase % processing pass complete for this transaction. Rows processed in tx: %. Work still exists for phase: %',
                job.id, phase, rows_processed_in_tx, work_still_exists_for_phase;

    RETURN work_still_exists_for_phase;
END;
$function$
```
