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
    v_error_keys_to_clear_arr TEXT[] := ARRAY['enterprise_link_for_legal_unit'];
    v_current_lu_data_row RECORD;
    v_existing_lu_record RECORD;
    v_resolved_enterprise_id INT;
    v_resolved_primary_for_enterprise BOOLEAN;
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

    -- For 'replace' actions, attempt to find the existing legal unit and its enterprise.
    -- If the legal unit is not found for a 'replace' action, it's a fatal error for this step.
    v_sql := format($$
        WITH lu_data AS (
            SELECT dt.row_id, lu.enterprise_id AS existing_enterprise_id, lu.primary_for_enterprise AS existing_primary_for_enterprise, lu.id as found_lu_id
            FROM public.%I dt
            LEFT JOIN public.legal_unit lu ON dt.legal_unit_id = lu.id
            WHERE dt.row_id = ANY(%L) AND dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL
        )
        UPDATE public.%I dt SET
            enterprise_id = CASE
                                WHEN dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL AND ld.found_lu_id IS NOT NULL THEN ld.existing_enterprise_id
                                ELSE dt.enterprise_id -- Keep existing or NULL for inserts/skipped/not found LU
                            END,
            primary_for_enterprise = CASE
                                        WHEN dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL AND ld.found_lu_id IS NOT NULL THEN ld.existing_primary_for_enterprise
                                        ELSE dt.primary_for_enterprise
                                     END,
            state = CASE
                        WHEN dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL AND ld.found_lu_id IS NULL THEN 'error'::public.import_data_state -- Fatal: LU for replace not found
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN dt.action = 'replace' AND dt.legal_unit_id IS NOT NULL AND ld.found_lu_id IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('enterprise_link_for_legal_unit', jsonb_build_object('legal_unit_not_found_for_replace', dt.legal_unit_id))
                        ELSE CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            last_completed_priority = %s -- Always v_step.priority
        FROM public.%I dt_main -- Alias for the main table being updated
        LEFT JOIN lu_data ld ON dt_main.row_id = ld.row_id
        WHERE dt_main.row_id = ANY(%L) AND dt_main.action = 'replace'; -- Only apply to 'replace' rows
    $$,
        v_data_table_name, p_batch_row_ids, -- For lu_data CTE
        v_data_table_name, -- For main UPDATE target
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, -- For error clearing
        v_step.priority, -- For LCP (always this step's priority)
        v_data_table_name, -- Alias for dt_main
        p_batch_row_ids    -- For final WHERE clause
    );

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating "replace" rows: %', p_job_id, v_sql;

    -- Debug loop before the actual update
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Debugging values for "replace" rows before update:', p_job_id;
    FOR v_current_lu_data_row IN EXECUTE format(
        'SELECT row_id, legal_unit_id, enterprise_id AS current_data_enterprise_id, primary_for_enterprise AS current_data_primary_for_enterprise, action FROM public.%I WHERE row_id = ANY(%L) AND action = ''replace''',
        v_data_table_name, p_batch_row_ids
    ) LOOP
        IF v_current_lu_data_row.legal_unit_id IS NOT NULL THEN
            SELECT lu.id, lu.enterprise_id, lu.primary_for_enterprise
            INTO v_existing_lu_record
            FROM public.legal_unit lu WHERE lu.id = v_current_lu_data_row.legal_unit_id;

            IF v_existing_lu_record.id IS NOT NULL THEN -- Corresponds to ld.found_lu_id IS NOT NULL
                v_resolved_enterprise_id := v_existing_lu_record.enterprise_id;
                v_resolved_primary_for_enterprise := v_existing_lu_record.primary_for_enterprise;
            ELSE
                v_resolved_enterprise_id := v_current_lu_data_row.current_data_enterprise_id; -- Would keep existing if LU not found
                v_resolved_primary_for_enterprise := v_current_lu_data_row.current_data_primary_for_enterprise;
            END IF;

            RAISE DEBUG '[Job %]   RowID: %, LU_ID_data: %, Found_LU_ID_db: %, Existing_Enterprise_ID_db: %, Current_Enterprise_ID_data: %, Resolved_Enterprise_ID_to_set: %',
                        p_job_id, v_current_lu_data_row.row_id, v_current_lu_data_row.legal_unit_id, v_existing_lu_record.id, v_existing_lu_record.enterprise_id, v_current_lu_data_row.current_data_enterprise_id, v_resolved_enterprise_id;
            RAISE DEBUG '[Job %]   RowID: %, Existing_Primary_db: %, Current_Primary_data: %, Resolved_Primary_to_set: %',
                        p_job_id, v_current_lu_data_row.row_id, v_existing_lu_record.primary_for_enterprise, v_current_lu_data_row.current_data_primary_for_enterprise, v_resolved_primary_for_enterprise;
        ELSE
            RAISE DEBUG '[Job %]   RowID: %, LU_ID_data: NULL, Skipping detailed lookup for this row.', p_job_id, v_current_lu_data_row.row_id;
        END IF;
    END LOOP;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT; -- This counts rows updated by the above SQL (action='replace')
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Processed % "replace" rows (includes potential errors).', p_job_id, v_processed_non_skip_count;

        -- Update priority for 'insert' and 'skip' rows, and 'replace' rows that were not processed by the first UPDATE (e.g. legal_unit_id was NULL)
        -- These rows are considered successful for this step's analysis phase or were already skipped.
        v_sql := format($$
            UPDATE public.%I dt SET
                last_completed_priority = %L,
                state = CASE WHEN dt.state != 'error' THEN 'analysing'::public.import_data_state ELSE dt.state END, -- Keep error state if already set
                error = CASE WHEN dt.state != 'error' THEN (CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END) ELSE dt.error END -- Clear this step's error if not an error from this step
            WHERE dt.row_id = ANY(%L)
              AND (dt.action = 'insert' OR dt.action = 'skip' OR (dt.action = 'replace' AND dt.last_completed_priority < %L));
        $$,
            v_data_table_name, v_step.priority,
            v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,
            p_batch_row_ids, v_step.priority
        );
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated priority/state for % other rows (insert/skip/unmatched_replace).', p_job_id, v_update_count;
        v_update_count := v_processed_non_skip_count + v_update_count; -- Total rows touched by logic in this procedure for this batch

    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_legal_unit: Error during batch update: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_legal_unit_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, replace(error_message, '%', '%%');
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
        -- lu_short_name VARCHAR(16), -- Removed, short_name will be NULL by default
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT -- Added
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, lu_name, edit_by_user_id, edit_at, edit_comment)
        SELECT row_id, name, edit_by_user_id, edit_at, edit_comment
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
            VALUES (NULL, rec_new_lu.edit_by_user_id, rec_new_lu.edit_at, rec_new_lu.edit_comment) -- Set short_name to NULL
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
    -- For new LUs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new LU linked to a new Enterprise are initially primary
            last_completed_priority = %L,
            error = NULL, -- Clear previous errors if this step succeeds for the row
            state = %L
        FROM temp_created_enterprises tce
        WHERE dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.row_id = ANY(%L) -- Ensure we only update rows from the current batch
          AND dt.state != 'error'; -- Avoid updating rows already in error from a prior step
    $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises and their related rows (action=insert): %', p_job_id, v_sql;
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
