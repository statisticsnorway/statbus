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
    v_external_ident_source_column_names_json JSONB;
    v_external_ident_source_columns TEXT[];
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

    -- Determine relevant source column names for external identifiers from the definition snapshot
    SELECT COALESCE(jsonb_agg(idc_element->>'column_name'), '[]'::jsonb)
    INTO v_external_ident_source_column_names_json
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc_element
    JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS isl_element
      ON (isl_element->>'code') = 'external_idents' AND (idc_element->>'step_id')::INT = (isl_element->>'id')::INT
    WHERE idc_element->>'purpose' = 'source_input';

    SELECT ARRAY(SELECT jsonb_array_elements_text(v_external_ident_source_column_names_json))
    INTO v_external_ident_source_columns;

    IF array_length(v_external_ident_source_columns, 1) IS NULL OR array_length(v_external_ident_source_columns, 1) = 0 THEN
        -- Fallback if no specific columns are found (should be rare for jobs with external_idents)
        v_external_ident_source_columns := ARRAY['unknown_identifier_source'];
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: No source_input columns found for external_idents step. Falling back to: %', p_job_id, v_external_ident_source_columns;
    ELSE
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Identified external_idents source_input columns: %', p_job_id, v_external_ident_source_columns;
    END IF;

    -- Create a temporary table to hold analysis results for 'replace' actions
    -- Per user guidance, explicit DROP is at the end / exception, not at the beginning for multi-call-in-one-tx test scenario.
    CREATE TEMP TABLE temp_enterprise_analysis_results (
        row_id BIGINT PRIMARY KEY,
        resolved_enterprise_id INT,
        resolved_primary_for_enterprise BOOLEAN,
        is_error BOOLEAN DEFAULT FALSE,
        error_details JSONB DEFAULT NULL
    ) ON COMMIT DROP;

    -- Populate the temp table for 'replace' actions.
    -- This handles potential fan-out if dt.legal_unit_id is a conceptual ID that maps to multiple
    -- temporal slices in public.legal_unit. It selects the latest temporally overlapping slice.
    v_sql := format($$
        INSERT INTO temp_enterprise_analysis_results (row_id, resolved_enterprise_id, resolved_primary_for_enterprise, is_error, error_details)
        SELECT
            dt.row_id,
            olu.enterprise_id, -- Enterprise ID from the latest LU slice
            olu.primary_for_enterprise_resolved, -- primary_for_enterprise from the latest LU slice
            CASE 
                WHEN dt.legal_unit_id IS NOT NULL AND olu.ref_lu_id_check IS NULL THEN TRUE -- legal_unit.id provided by external_idents, but no LU data row found for it in public.legal_unit
                ELSE FALSE 
            END AS is_error,
            CASE
                WHEN dt.legal_unit_id IS NOT NULL AND olu.ref_lu_id_check IS NULL THEN 
                    (SELECT jsonb_object_agg(col_name, jsonb_build_object(
                        'error_code', 'LU_DATA_MISSING_FOR_ID',
                        'message', 'Legal Unit was identified by an external identifier (resolving to internal ID ' || dt.legal_unit_id::TEXT || '), but no corresponding data row was found in public.legal_unit using this internal ID.',
                        'internal_lu_id', dt.legal_unit_id
                    )) FROM unnest($2) AS col_name) -- $2 is v_external_ident_source_columns
                ELSE NULL
            END AS error_details
        FROM public.%I dt -- This is v_data_table_name
        LEFT JOIN LATERAL (
            SELECT
                ref_lu.id AS ref_lu_id_check, -- To confirm a legal_unit row was actually found
                ref_lu.enterprise_id,
                COALESCE(ref_lu.primary_for_enterprise, FALSE) AS primary_for_enterprise_resolved
            FROM public.legal_unit ref_lu
            WHERE ref_lu.id = dt.legal_unit_id -- Match conceptual LU ID stored in dt.legal_unit_id
            ORDER BY ref_lu.valid_after DESC, ref_lu.valid_to DESC -- Get the latest slice
            LIMIT 1
        ) olu ON TRUE -- olu will have 0 or 1 row
        WHERE dt.row_id = ANY($1) -- Process only rows in the current batch
          AND dt.action = 'replace'
          AND dt.legal_unit_id IS NOT NULL; -- Only attempt this for rows that have a legal_unit_id (identified by external_idents)
    $$, v_data_table_name);

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Populating temp_enterprise_analysis_results for "replace" actions (using placeholder for batch_row_ids and external_ident_cols): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids, v_external_ident_source_columns; -- Pass parameters via USING clause
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows inserted into temp table
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Populated % rows into temp_enterprise_analysis_results.', p_job_id, v_update_count;

    BEGIN
        -- Update the main data table from the temp table results
        v_sql := format($$
            UPDATE public.%I dt SET
                enterprise_id = tear.resolved_enterprise_id,
                primary_for_enterprise = tear.resolved_primary_for_enterprise,
                state = CASE WHEN tear.is_error THEN 'error'::public.import_data_state ELSE 'analysing'::public.import_data_state END,
                error = CASE
                            WHEN tear.is_error THEN COALESCE(dt.error, '{}'::jsonb) || tear.error_details
                            ELSE CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                        END,
                last_completed_priority = %s
            FROM temp_enterprise_analysis_results tear
            WHERE dt.row_id = tear.row_id;
        $$, v_data_table_name, v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, v_step.priority);

        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating _data table from temp_enterprise_analysis_results: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated % rows in _data table from temp table.', p_job_id, v_processed_non_skip_count;

        -- Update priority for rows not processed by the temp table logic
        -- This includes 'insert', 'skip', and 'replace' rows where legal_unit_id was NULL (so not in temp table).
        -- These rows are considered successful for this step's analysis phase or were already skipped/had no LU to link.
        v_sql := format($$
            UPDATE public.%I dt SET
                last_completed_priority = %L,
                state = CASE WHEN dt.state != 'error' THEN 'analysing'::public.import_data_state ELSE dt.state END, -- Keep error state if already set
                error = CASE WHEN dt.state != 'error' THEN (CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END) ELSE dt.error END -- Clear this step's error if not an error from this step
            WHERE dt.row_id = ANY(%L)
              AND NOT EXISTS (SELECT 1 FROM temp_enterprise_analysis_results tear WHERE tear.row_id = dt.row_id);
        $$,
            v_data_table_name, v_step.priority,
            v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,
            p_batch_row_ids
        );

        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating LCP for remaining rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated LCP for % remaining rows (insert/skip/unmatched_replace).', p_job_id, v_update_count;
        v_update_count := v_processed_non_skip_count + v_update_count; -- Total rows touched by logic in this procedure for this batch

    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_legal_unit: Error during batch update: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_legal_unit_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Marked job as failed due to error: %', p_job_id, replace(error_message, '%', '%%');
        
        -- Ensure cleanup on error
        DROP TABLE IF EXISTS temp_enterprise_analysis_results;
        RAISE;
    END;

    -- Ensure cleanup on successful completion of this block
    DROP TABLE IF EXISTS temp_enterprise_analysis_results;
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
        data_row_id BIGINT PRIMARY KEY, -- This will be the founding_row_id for the new LU entity
        lu_name TEXT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, lu_name, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.name, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%I dt
        WHERE dt.row_id = ANY(%L) AND dt.action = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new LUs
    $$, v_data_table_name, p_batch_row_ids);
    EXECUTE v_sql;

    -- Step 2: Create new enterprises for LUs in temp_new_lu_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the LU
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id BIGINT PRIMARY KEY, -- Stores the founding_row_id of the LU
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
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
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
