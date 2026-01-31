-- Migration 20260131220347: add_batch_seq_state_check_constraint
-- Adds a CHECK constraint to import data tables ensuring batch_seq, state, and action
-- are consistent with each other.
--
-- Also updates the state machine to set batch_seq and state atomically to satisfy the constraint.
BEGIN;

-- Update import_job_assign_batch_seq to atomically set state when transitioning to analysis phase.
-- This ensures the CHECK constraint is satisfied (state='analysing' requires batch_seq IS NOT NULL).
-- Also supports resetting last_completed_priority in the same UPDATE to minimize UPDATE count.
CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(
    p_data_table_name TEXT,
    p_batch_size INTEGER,
    p_for_processing BOOLEAN DEFAULT FALSE,
    p_new_state public.import_data_state DEFAULT NULL,  -- Optional: atomically set state when assigning batch_seq
    p_reset_priority BOOLEAN DEFAULT FALSE              -- Optional: reset last_completed_priority to 0
) RETURNS INTEGER
LANGUAGE plpgsql AS $import_job_assign_batch_seq$
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
        $$, p_data_table_name, p_batch_size, v_extra_sets);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$import_job_assign_batch_seq$;


-- Update import_job_process to use atomic state+batch_seq assignment.
-- This is a large procedure, so we replace it entirely.
CREATE OR REPLACE PROCEDURE admin.import_job_process(job_id integer)
LANGUAGE plpgsql AS $import_job_process$
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
$import_job_process$;


-- Update the import_job_generate function to include the CHECK constraint
-- when creating new import data tables.
CREATE OR REPLACE FUNCTION admin.import_job_generate(job public.import_job)
RETURNS void SECURITY DEFINER LANGUAGE plpgsql AS $import_job_generate$
DECLARE
    create_upload_table_stmt text;
    create_data_table_stmt text;
    add_separator BOOLEAN := FALSE;
    col_rec RECORD;
    source_col_rec RECORD;
BEGIN
    RAISE DEBUG '[Job %] Generating tables: %, %', job.id, job.upload_table_name, job.data_table_name;

    -- 1. Create Upload Table using job.definition_snapshot as the single source of truth
    RAISE DEBUG '[Job %] Generating upload table % from snapshot', job.id, job.upload_table_name;
    create_upload_table_stmt := format('CREATE TABLE public.%I (', job.upload_table_name);
    add_separator := FALSE;

    FOR source_col_rec IN
        SELECT * FROM jsonb_to_recordset(job.definition_snapshot->'import_source_column_list')
            AS x(id int, definition_id int, column_name text, priority int, created_at timestamptz, updated_at timestamptz)
        ORDER BY priority
    LOOP
        IF add_separator THEN
            create_upload_table_stmt := create_upload_table_stmt || ', ';
        END IF;
        create_upload_table_stmt := create_upload_table_stmt || format('%I TEXT', source_col_rec.column_name);
        add_separator := TRUE;
    END LOOP;
    create_upload_table_stmt := create_upload_table_stmt || ');';

    RAISE DEBUG '[Job %] Upload table DDL: %', job.id, create_upload_table_stmt;
    EXECUTE create_upload_table_stmt;

    -- Add triggers to upload table
    EXECUTE format($$
        CREATE TRIGGER %I
        BEFORE INSERT ON public.%I FOR EACH STATEMENT
        EXECUTE FUNCTION admin.check_import_job_state_for_insert(%L);$$,
        job.upload_table_name || '_check_state_before_insert', job.upload_table_name, job.slug);
    EXECUTE format($$
        CREATE TRIGGER %I
        AFTER INSERT ON public.%I FOR EACH STATEMENT
        EXECUTE FUNCTION admin.update_import_job_state_after_insert(%L);$$,
        job.upload_table_name || '_update_state_after_insert', job.upload_table_name, job.slug);
    RAISE DEBUG '[Job %] Added triggers to upload table %', job.id, job.upload_table_name;

    -- 2. Create Data Table using job.definition_snapshot as the single source of truth
    RAISE DEBUG '[Job %] Generating data table % from snapshot', job.id, job.data_table_name;
    -- Add row_id as the first column and primary key
    create_data_table_stmt := format('CREATE TABLE public.%I (row_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, batch_seq INTEGER, ', job.data_table_name);
    add_separator := FALSE; -- Reset for data table columns

    -- Add columns based on import_data_column records from the job's definition snapshot.
    -- The snapshot list is already correctly ordered by step priority then column priority.
    FOR col_rec IN
        SELECT *
        FROM jsonb_to_recordset(job.definition_snapshot->'import_data_column_list') AS x(
            id integer,
            step_id int,
            priority int,
            column_name text,
            column_type text,
            purpose public.import_data_column_purpose,
            is_nullable boolean,
            default_value text,
            is_uniquely_identifying boolean,
            created_at timestamptz,
            updated_at timestamptz
        )
    LOOP
        IF add_separator THEN
            create_data_table_stmt := create_data_table_stmt || ', ';
        END IF;
        create_data_table_stmt := create_data_table_stmt || format('%I %s', col_rec.column_name, col_rec.column_type);
        IF NOT col_rec.is_nullable THEN
            create_data_table_stmt := create_data_table_stmt || ' NOT NULL';
        END IF;
        IF col_rec.default_value IS NOT NULL THEN
            create_data_table_stmt := create_data_table_stmt || format(' DEFAULT %s', col_rec.default_value);
        END IF;
        add_separator := TRUE;
    END LOOP;

    -- Add the CHECK constraint for batch_seq/state/action consistency
    create_data_table_stmt := create_data_table_stmt || $constraint$,
    CONSTRAINT chk_batch_seq_state_action CHECK (
      CASE state
        WHEN 'pending' THEN batch_seq IS NULL AND action IS NULL
        WHEN 'analysing' THEN batch_seq IS NOT NULL
        WHEN 'analysed' THEN batch_seq IS NOT NULL AND action IS NOT NULL
        WHEN 'error' THEN TRUE
        WHEN 'processing' THEN action = 'use' AND batch_seq IS NOT NULL
        WHEN 'processed' THEN action = 'use' AND batch_seq IS NOT NULL
        ELSE FALSE
      END
    )$constraint$;

    create_data_table_stmt := create_data_table_stmt || ');';

    RAISE DEBUG '[Job %] Data table DDL: %', job.id, create_data_table_stmt;
    EXECUTE create_data_table_stmt;


  -- Create composite index (state, last_completed_priority, batch_seq) for efficient batch selection.
  -- The batch selection query uses: WHERE state IN ('analysing', 'error') AND last_completed_priority < priority
  -- and then SELECT MIN(batch_seq), so having batch_seq in the index allows index-only scans.
  EXECUTE format($$CREATE INDEX ON public.%1$I (state, last_completed_priority, batch_seq)$$, job.data_table_name /* %1$I */);
  RAISE DEBUG '[Job %] Added composite index (state, last_completed_priority, batch_seq) to data table %', job.id, job.data_table_name;

  -- The GIST index on row_id has been removed. The `analyse_valid_time` procedure,
  -- which was the sole user of this index via the `<@` operator, has been refactored
  -- to use an `unnest`/`JOIN` strategy that leverages the much faster B-tree primary key index.

  -- Add GIST index on daterange(valid_from, valid_until) for efficient temporal_merge lookups.
  EXECUTE format('CREATE INDEX ON public.%I USING GIST (daterange(valid_from, valid_until, ''[)''))', job.data_table_name);
  RAISE DEBUG '[Job %] Added GIST index on validity daterange to data table %', job.id, job.data_table_name;

  EXECUTE format('CREATE INDEX ON public.%I (batch_seq) WHERE batch_seq IS NOT NULL', job.data_table_name);
  RAISE DEBUG '[Job %] Added btree index on batch_seq for efficient processing phase lookups %', job.id, job.data_table_name;

  -- Create indexes on uniquely identifying source_input columns to speed up lookups within analysis steps.
  FOR col_rec IN
      SELECT (x->>'column_name')::TEXT as column_name
      FROM jsonb_array_elements(job.definition_snapshot->'import_data_column_list') x
      WHERE x->>'purpose' = 'source_input' AND (x->>'is_uniquely_identifying')::boolean IS TRUE
  LOOP
      RAISE DEBUG '[Job %] Adding index on uniquely identifying source column: %', job.id, col_rec.column_name;
      EXECUTE format('CREATE INDEX ON public.%I (%I)', job.data_table_name, col_rec.column_name);
  END LOOP;

  -- Add recommended performance indexes.
  BEGIN
      -- Add index on founding_row_id. This helps with error propagation and is now a standard column.
      EXECUTE format(
          $$ CREATE INDEX ON public.%1$I (founding_row_id) WHERE founding_row_id IS NOT NULL $$,
          job.data_table_name
      );
      RAISE DEBUG '[Job %] Added founding_row_id index to data table %.', job.id, job.data_table_name;

      -- The partial indexes on (COALESCE(founding_row_id, row_id)) have been removed.
      -- They were specific to a previous, more complex batching strategy and are no longer
      -- used by the simplified batch selection queries, which now efficiently use the
      -- composite index on (state, last_completed_priority, batch_seq).

      -- NOTE: The (state, action, row_id) index has been removed. It was designed for the old
      -- row_id-based batching approach. The new batch_seq approach uses the composite index
      -- (state, last_completed_priority, batch_seq) for batch selection instead.
  END;

  -- Grant direct permissions to the job owner on the upload table to allow COPY FROM
  DECLARE
      job_user_role_name TEXT;
  BEGIN
      SELECT u.email INTO job_user_role_name
      FROM auth.user u
      WHERE u.id = job.user_id;

      IF job_user_role_name IS NOT NULL THEN
          EXECUTE format($$GRANT ALL ON TABLE public.%I TO %I$$, job.upload_table_name, job_user_role_name);
          RAISE DEBUG '[Job %] Granted ALL on % to role %', job.id, job.upload_table_name, job_user_role_name;
      ELSE
          RAISE WARNING '[Job %] Could not find user role for user_id %, cannot grant permissions on %',
                        job.id, job.user_id, job.upload_table_name;
      END IF;
  END;

  -- Apply standard RLS to the data table
  PERFORM admin.add_rls_regular_user_can_edit(job.data_table_name::regclass);
  RAISE DEBUG '[Job %] Applied RLS to data table %', job.id, job.data_table_name;

  -- Ensure the new tables are available through PostgREST
  NOTIFY pgrst, 'reload schema';
  RAISE DEBUG '[Job %] Notified PostgREST to reload schema', job.id;
END;
$import_job_generate$;

END;
