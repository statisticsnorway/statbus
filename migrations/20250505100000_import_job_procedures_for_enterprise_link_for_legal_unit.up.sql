-- Migration: import_job_procedures_for_enterprise_link_for_legal_unit
-- Implements the analyse and process procedures for the enterprise_link import step.

BEGIN;

-- Procedure to analyse enterprise link (find existing enterprise for existing LUs)
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_processed_non_skip_count INT := 0; -- To track rows handled by the first main update
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_job_mode public.import_mode;
    error_message TEXT; 
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Starting analysis for % rows. Batch Row IDs: %', p_job_id, array_length(p_batch_row_ids, 1), p_batch_row_ids;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''.', p_job_id, v_job_mode;
        EXECUTE format('UPDATE public.%I SET last_completed_priority = (SELECT priority FROM public.import_step WHERE code = %L) WHERE row_id = ANY(%L)', 
                       v_data_table_name, p_step_code, p_batch_row_ids);
        RETURN;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_legal_unit step not found', p_job_id; END IF;

    -- Single-pass update for existing LUs (action='replace')
    -- For new LUs (action='insert'), enterprise_id and primary_for_enterprise will be set by process_enterprise_link_for_legal_unit
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = CASE
                                WHEN dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL THEN lu.enterprise_id
                                ELSE dt.enterprise_id -- Keep existing or NULL for inserts/skipped
                            END,
            primary_for_enterprise = lu.primary_for_enterprise,
            last_completed_priority = %L,
            state = 'analysing'::public.import_data_state -- Set to analysing for these rows
        FROM public.legal_unit lu
        WHERE dt.row_id = ANY(%L) 
          AND dt.action = 'replace' 
          AND dt.legal_unit_id = lu.id; -- Join condition for 'replace'
    $$, v_data_table_name, v_step.priority, p_batch_row_ids);
    
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating enterprise links for "replace" rows: %', p_job_id, v_sql;
    
    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated % "replace" rows.', p_job_id, v_processed_non_skip_count;

        -- Update priority for skipped rows
        v_sql := format($$
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = 'skip';
        $$, v_data_table_name, v_step.priority, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated priority for % "skip" rows.', p_job_id, v_skipped_update_count;

        -- Update other non-skipped rows (e.g. action='insert', or 'replace' that didn't match LU)
        v_sql := format($$
            UPDATE public.%I dt SET
                last_completed_priority = %L,
                state = 'analysing'::public.import_data_state
            WHERE dt.row_id = ANY(%L) 
              AND dt.action != 'skip'
              AND dt.last_completed_priority < %L; -- Only update if not already processed by the first update or skip update
        $$, v_data_table_name, v_step.priority, p_batch_row_ids, v_step.priority);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated priority for % other non-skip rows (insert/unmatched_replace).', p_job_id, v_update_count;
        v_update_count := v_processed_non_skip_count + v_skipped_update_count + v_update_count;
    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_legal_unit: Error during batch update: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_legal_unit_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Finished analysis successfully.', p_job_id;
END;
$analyse_enterprise_link_for_legal_unit$;


-- Procedure to process enterprise link (create enterprise for new LUs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT; -- For main exception handler
    rec_new_lu RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''.', p_job_id, v_job_mode;
        EXECUTE format('UPDATE public.%I SET last_completed_priority = (SELECT priority FROM public.import_step WHERE code = %L) WHERE row_id = ANY(%L)', 
                       v_data_table_name, p_step_code, p_batch_row_ids);
        RETURN;
    END IF;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link step not found', p_job_id; END IF;

    -- Step 1: Identify rows needing enterprise creation (new LUs, action = 'insert')
    CREATE TEMP TABLE temp_new_lu_for_enterprise_creation (
        data_row_id BIGINT PRIMARY KEY,
        lu_name TEXT,
        lu_short_name VARCHAR(16),
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT -- Added
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, lu_name, lu_short_name, edit_by_user_id, edit_at, edit_comment)
        SELECT row_id, name, SUBSTRING(name FROM 1 FOR 16), edit_by_user_id, edit_at, edit_comment
        FROM public.%I
        WHERE row_id = ANY(%L) AND action = 'insert'; -- Only process rows for new LUs
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    -- Step 2: Create new enterprises for LUs in temp_new_lu_for_enterprise_creation and map them
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id BIGINT PRIMARY KEY,
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        FOR rec_new_lu IN SELECT * FROM temp_new_lu_for_enterprise_creation LOOP
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            VALUES (rec_new_lu.lu_short_name, rec_new_lu.edit_by_user_id, rec_new_lu.edit_at, rec_new_lu.edit_comment)
            RETURNING id INTO new_enterprise_id;

            INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
            VALUES (rec_new_lu.data_row_id, new_enterprise_id);
            v_created_enterprise_count := v_created_enterprise_count + 1;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_lu', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE; 
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert')
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = true, -- Assume new LU is primary for new enterprise
            last_completed_priority = %L,
            error = NULL, -- Clear previous errors if this step succeeds for the row
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.row_id = tce.data_row_id; -- Join on data_row_id
    $$, v_data_table_name, v_step.priority, 'processing');
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            state = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action = 'replace' -- Only update rows for existing LUs
          AND dt.state != %L; -- Avoid rows already in error
    $$, v_data_table_name, v_step.priority, 'processing', p_batch_row_ids, 'error');
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 5: Update skipped rows (action = 'skip') - just advance priority
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation. Linked % LUs to enterprises (includes new and existing).', p_job_id, v_update_count; -- v_update_count here is from the last UPDATE (skipped rows)

    DROP TABLE IF EXISTS temp_new_lu_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure cleanup even on unexpected error
    DROP TABLE IF EXISTS temp_new_lu_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_legal_unit_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$process_enterprise_link_for_legal_unit$;

COMMIT;
