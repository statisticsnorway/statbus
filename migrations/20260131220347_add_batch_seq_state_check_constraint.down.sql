-- Down Migration 20260131220347: add_batch_seq_state_check_constraint
-- Restores the original functions without the CHECK constraint.
BEGIN;

-- Restore original import_job_assign_batch_seq (without p_new_state parameter)
CREATE OR REPLACE FUNCTION admin.import_job_assign_batch_seq(
    p_data_table_name TEXT,
    p_batch_size INTEGER,
    p_for_processing BOOLEAN DEFAULT FALSE
) RETURNS INTEGER
LANGUAGE plpgsql AS $import_job_assign_batch_seq$
DECLARE
    v_total_rows INTEGER;
BEGIN
    IF p_for_processing THEN
        -- For processing phase: assign batch_seq only to rows with action = 'use'.
        -- First NULL out all batch_seq, then re-assign to relevant rows.
        EXECUTE format($$UPDATE public.%1$I SET batch_seq = NULL$$, p_data_table_name);
        
        EXECUTE format($$
            WITH numbered AS (
                SELECT row_id, 
                       ((row_number() OVER (ORDER BY row_id) - 1) / %2$L + 1)::INTEGER as batch_num
                FROM public.%1$I
                WHERE action = 'use'
            )
            UPDATE public.%1$I dt
            SET batch_seq = numbered.batch_num
            FROM numbered
            WHERE dt.row_id = numbered.row_id
        $$, p_data_table_name, p_batch_size);
    ELSE
        -- For analysis phase: assign batch_seq to ALL rows.
        EXECUTE format($$
            UPDATE public.%1$I
            SET batch_seq = ((row_id - 1) / %2$L + 1)::INTEGER
        $$, p_data_table_name, p_batch_size);
    END IF;
    
    GET DIAGNOSTICS v_total_rows = ROW_COUNT;
    RETURN v_total_rows;
END;
$import_job_assign_batch_seq$;


-- Restore original import_job_process (without atomic state+batch_seq assignment)
CREATE OR REPLACE PROCEDURE admin.import_job_process(job_id integer)
LANGUAGE plpgsql AS $import_job_process$
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
            should_reschedule := TRUE;

        WHEN 'preparing_data' THEN
            DECLARE
                v_data_row_count BIGINT;
            BEGIN
                RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
                PERFORM admin.import_job_prepare(job);

                EXECUTE format('SELECT COUNT(*) FROM public.%I', job.data_table_name) INTO v_data_row_count;

                UPDATE public.import_job
                SET
                    total_rows = v_data_row_count,
                    total_analysis_steps_weighted = v_data_row_count * max_analysis_priority
                WHERE id = job.id
                RETURNING * INTO job;

                RAISE DEBUG '[Job %] Recounted total_rows to % and updated total_analysis_steps_weighted.', job.id, job.total_rows;

                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                -- Transition rows in _data table from 'pending' to 'analysing'
                RAISE DEBUG '[Job %] Updating data rows from pending to analysing in table %', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L$$, job.data_table_name, 'analysing'::public.import_data_state, 'pending'::public.import_data_state);
                
                -- PERFORMANCE: Assign initial batch_seq for analysis phase (all rows)
                RAISE DEBUG '[Job %] Assigning initial batch_seq values with batch_size % for analysis', job_id, job.analysis_batch_size;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.analysis_batch_size, FALSE);
                
                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE;
            END;

        WHEN 'analysing_data' THEN
            DECLARE
                v_completed_steps_weighted BIGINT;
                v_old_step_code TEXT;
            BEGIN
                RAISE DEBUG '[Job %] Starting analysis phase.', job_id;

                v_old_step_code := job.current_step_code;

                should_reschedule := admin.import_job_analysis_phase(job);

                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                IF job.max_analysis_priority IS NOT NULL AND (
                    job.current_step_code IS DISTINCT FROM v_old_step_code
                    OR NOT should_reschedule
                ) THEN
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
                ELSIF NOT should_reschedule THEN
                    IF job.review THEN
                        RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                        EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND action = 'use'$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                        job := admin.import_job_set_state(job, 'waiting_for_review');
                        RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    ELSE
                        RAISE DEBUG '[Job %] Updating data rows from analysing to processing and resetting LCP in table %', job_id, job.data_table_name;
                        EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L AND action = 'use'$$, job.data_table_name, 'processing'::public.import_data_state, 'analysing'::public.import_data_state);

                        RAISE DEBUG '[Job %] Re-assigning batch_seq values with batch_size % for processing', job_id, job.processing_batch_size;
                        PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE);

                        RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                        EXECUTE format('ANALYZE public.%I', job.data_table_name);

                        job := admin.import_job_set_state(job, 'processing_data');
                        RAISE DEBUG '[Job %] Analysis complete, proceeding to processing.', job_id;
                        should_reschedule := TRUE;
                    END IF;
                END IF;
            END;

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            BEGIN
                RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
                RAISE DEBUG '[Job %] Updating data rows from analysed to processing and resetting LCP in table % after approval', job_id, job.data_table_name;
                EXECUTE format($$UPDATE public.%I SET state = %L, last_completed_priority = 0 WHERE state = %L AND action = 'use'$$, job.data_table_name, 'processing'::public.import_data_state, 'analysed'::public.import_data_state);

                RAISE DEBUG '[Job %] Re-assigning batch_seq values with batch_size % for processing', job_id, job.processing_batch_size;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE);

                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'processing_data');
                should_reschedule := TRUE;
            END;

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            BEGIN
                RAISE DEBUG '[Job %] Starting processing phase.', job_id;

                should_reschedule := admin.import_job_processing_phase(job);

                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                RAISE DEBUG '[Job %] Processing phase batch complete. imported_rows: %', job.id, job.imported_rows;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during processing phase: %. Job already transitioned to finished.', job.id, job.error;
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN
                    job := admin.import_job_set_state(job, 'finished');
                    RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
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


-- Restore original import_job_generate (without CHECK constraint)
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

    RAISE DEBUG '[Job %] Generating data table % from snapshot', job.id, job.data_table_name;
    create_data_table_stmt := format('CREATE TABLE public.%I (row_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, batch_seq INTEGER, ', job.data_table_name);
    add_separator := FALSE;

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

    create_data_table_stmt := create_data_table_stmt || ');';

    RAISE DEBUG '[Job %] Data table DDL: %', job.id, create_data_table_stmt;
    EXECUTE create_data_table_stmt;

  EXECUTE format($$CREATE INDEX ON public.%1$I (state, last_completed_priority, row_id)$$, job.data_table_name);
  RAISE DEBUG '[Job %] Added composite index to data table %', job.id, job.data_table_name;

  EXECUTE format('CREATE INDEX ON public.%I USING GIST (daterange(valid_from, valid_until, ''[)''))', job.data_table_name);
  RAISE DEBUG '[Job %] Added GIST index on validity daterange to data table %', job.id, job.data_table_name;

  EXECUTE format('CREATE INDEX ON public.%I (batch_seq) WHERE batch_seq IS NOT NULL', job.data_table_name);
  RAISE DEBUG '[Job %] Added btree index on batch_seq for efficient processing phase lookups %', job.id, job.data_table_name;

  FOR col_rec IN
      SELECT (x->>'column_name')::TEXT as column_name
      FROM jsonb_array_elements(job.definition_snapshot->'import_data_column_list') x
      WHERE x->>'purpose' = 'source_input' AND (x->>'is_uniquely_identifying')::boolean IS TRUE
  LOOP
      RAISE DEBUG '[Job %] Adding index on uniquely identifying source column: %', job.id, col_rec.column_name;
      EXECUTE format('CREATE INDEX ON public.%I (%I)', job.data_table_name, col_rec.column_name);
  END LOOP;

  BEGIN
      EXECUTE format(
          $$ CREATE INDEX ON public.%1$I (founding_row_id) WHERE founding_row_id IS NOT NULL $$,
          job.data_table_name
      );
      RAISE DEBUG '[Job %] Added founding_row_id index to data table %.', job.id, job.data_table_name;

      EXECUTE format(
          $$ CREATE INDEX ON public.%1$I (state, action, row_id) $$,
          job.data_table_name
      );
      RAISE DEBUG '[Job %] Added (state, action, row_id) index for processing phase batch selection.', job.id;
  END;

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

  PERFORM admin.add_rls_regular_user_can_edit(job.data_table_name::regclass);
  RAISE DEBUG '[Job %] Applied RLS to data table %', job.id, job.data_table_name;

  NOTIFY pgrst, 'reload schema';
  RAISE DEBUG '[Job %] Notified PostgREST to reload schema', job.id;
END;
$import_job_generate$;

END;
