-- Migration: import_job_procedures_for_enterprise_link_for_legal_unit
-- Implements the analyse and process procedures for the enterprise_link import step.

BEGIN;

-- Procedure to analyse enterprise link (find existing enterprise for existing LUs)
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
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
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_legal_unit step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''.', p_job_id, v_job_mode;
        v_sql := format($$UPDATE public.%1$I SET last_completed_priority = %2$L WHERE row_id <@ $1$$, 
                       v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Advancing priority for skipped (wrong mode) batch with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        RETURN;
    END IF;

    -- Determine relevant source column names for external identifiers from the definition snapshot
    SELECT COALESCE(jsonb_agg(idc_elem.value->>'column_name'), '[]'::jsonb)
    INTO v_external_ident_source_column_names_json
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc_elem
    JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS step_elem
      ON (step_elem.value->>'code') = 'external_idents' AND (idc_elem.value->>'step_id')::INT = (step_elem.value->>'id')::INT
    WHERE idc_elem.value->>'purpose' = 'source_input';

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
    IF to_regclass('pg_temp.temp_enterprise_analysis_results') IS NOT NULL THEN DROP TABLE temp_enterprise_analysis_results; END IF;
    CREATE TEMP TABLE temp_enterprise_analysis_results (
        row_id INTEGER PRIMARY KEY,
        resolved_enterprise_id INT,
        resolved_primary_for_enterprise BOOLEAN,
        is_error BOOLEAN DEFAULT FALSE,
        error_details JSONB DEFAULT NULL
    ) ON COMMIT DROP;

    -- Populate the temp table for 'replace' actions.
    -- This handles potential fan-out if dt.legal_unit_id is a conceptual ID that maps to multiple
    -- temporal slices in public.legal_unit. It selects the latest temporally overlapping slice.
    v_sql := format($$
        WITH
        BatchLUs AS (
            SELECT row_id, legal_unit_id
            FROM public.%1$I
            WHERE row_id <@ $1 AND action = 'use' AND operation = 'replace' AND legal_unit_id IS NOT NULL
        ),
        DistinctLUIDs AS (
            SELECT DISTINCT legal_unit_id FROM BatchLUs
        ),
        LatestSlices AS (
            SELECT DISTINCT ON (id)
                id AS ref_lu_id_check,
                enterprise_id,
                COALESCE(primary_for_enterprise, FALSE) AS primary_for_enterprise_resolved
            FROM public.legal_unit
            WHERE id IN (SELECT legal_unit_id FROM DistinctLUIDs)
            ORDER BY id, valid_from DESC, valid_until DESC
        )
        INSERT INTO temp_enterprise_analysis_results (row_id, resolved_enterprise_id, resolved_primary_for_enterprise, is_error, error_details)
        SELECT
            dt.row_id,
            olu.enterprise_id,
            olu.primary_for_enterprise_resolved,
            CASE
                WHEN dt.legal_unit_id IS NOT NULL AND olu.ref_lu_id_check IS NULL THEN TRUE
                ELSE FALSE
            END AS is_error,
            CASE
                WHEN dt.legal_unit_id IS NOT NULL AND olu.ref_lu_id_check IS NULL THEN
                    (SELECT jsonb_object_agg(col_name, jsonb_build_object(
                        'error_code', 'LU_DATA_MISSING_FOR_ID',
                        'message', 'Legal Unit was identified by an external identifier (resolving to internal ID ' || dt.legal_unit_id::TEXT || '), but no corresponding data row was found in public.legal_unit using this internal ID.',
                        'internal_lu_id', dt.legal_unit_id
                    )) FROM unnest($2) AS col_name)
                ELSE NULL
            END AS error_details
        FROM BatchLUs dt
        LEFT JOIN LatestSlices olu ON dt.legal_unit_id = olu.ref_lu_id_check;
    $$, v_data_table_name /* %1$I */);

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Populating temp_enterprise_analysis_results for "replace" actions (using placeholder for batch_row_id_ranges and external_ident_cols): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges, v_external_ident_source_columns; -- Pass parameters via USING clause
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows inserted into temp table
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Populated % rows into temp_enterprise_analysis_results.', p_job_id, v_update_count;

    BEGIN
        -- Update the main data table from the temp table results
        v_sql := format($$
            UPDATE public.%1$I dt SET
                enterprise_id = tear.resolved_enterprise_id,
                primary_for_enterprise = tear.resolved_primary_for_enterprise,
                state = CASE WHEN tear.is_error THEN 'error'::public.import_data_state ELSE 'analysing'::public.import_data_state END,
                errors = CASE
                            WHEN tear.is_error THEN dt.errors || tear.error_details
                            ELSE dt.errors - %2$L::TEXT[]
                        END,
                last_completed_priority = %3$L
            FROM temp_enterprise_analysis_results tear
            WHERE dt.row_id = tear.row_id;
        $$, v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */, v_step.priority /* %3$L */);

        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating _data table from temp_enterprise_analysis_results: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updated % rows in _data table from temp table.', p_job_id, v_processed_non_skip_count;

        -- Update priority for rows not processed by the temp table logic
        -- This includes 'insert' and 'replace' rows where legal_unit_id was NULL. Skipped rows are not touched.
        -- These rows are considered successful for this step's analysis phase.
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L,
                state = 'analysing'::public.import_data_state,
                errors = dt.errors - %3$L::TEXT[] -- Clear this step's error if not an error from this step
            WHERE dt.row_id <@ $1
              AND dt.action IS DISTINCT FROM 'skip'
              AND NOT EXISTS (SELECT 1 FROM temp_enterprise_analysis_results tear WHERE tear.row_id = dt.row_id);
        $$,
            v_data_table_name /* %1$I */, v_step.priority /* %2$L */,
            v_error_keys_to_clear_arr /* %3$L */
        );

        RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit: Updating LCP for remaining rows: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
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
        
        RAISE;
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, 'analyse_enterprise_link_for_legal_unit');

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I SET last_completed_priority = %2$L WHERE row_id <@ $1 AND last_completed_priority < %2$L',
                   v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_legal_unit (Batch): Finished analysis successfully.', p_job_id;
END;
$analyse_enterprise_link_for_legal_unit$;


-- Procedure to process enterprise link (create enterprise for new LUs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_legal_unit$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT; -- For main exception handler
    rec_new_lu RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Starting operation for range %s', p_job_id, p_batch_row_id_ranges::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_legal_unit step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'legal_unit' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Skipping, job mode is %, not ''legal_unit''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new LUs, action = 'insert')
    IF to_regclass('pg_temp.temp_new_lu_for_enterprise_creation') IS NOT NULL THEN DROP TABLE temp_new_lu_for_enterprise_creation; END IF;
    CREATE TEMP TABLE temp_new_lu_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new LU entity
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_lu_for_enterprise_creation (data_row_id, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.row_id <@ $1 AND dt.action = 'use' AND dt.operation = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new LUs
    $$, v_data_table_name /* %1$I */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Populating temp table for new LUs with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;

    -- Step 2: Create new enterprises for LUs in temp_new_lu_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the LU
    IF to_regclass('pg_temp.temp_created_enterprises') IS NOT NULL THEN DROP TABLE temp_created_enterprises; END IF;
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the LU
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        WITH new_enterprises AS (
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            SELECT
                NULL, -- short_name is set to NULL, will be derived by trigger later
                t.edit_by_user_id,
                t.edit_at,
                t.edit_comment
            FROM temp_new_lu_for_enterprise_creation t
            RETURNING id
        ),
        -- This mapping is tricky because INSERT...RETURNING doesn't give us back the source rows.
        -- We rely on the fact that the order should be preserved and join by row_number.
        -- This is safe as we are in a single transaction and not using parallel workers.
        source_with_rn AS (
            SELECT *, ROW_NUMBER() OVER () as rn FROM temp_new_lu_for_enterprise_creation
        ),
        created_with_rn AS (
            SELECT id, ROW_NUMBER() OVER () as rn FROM new_enterprises
        )
        INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
        SELECT s.data_row_id, c.id
        FROM source_with_rn s
        JOIN created_with_rn c ON s.rn = c.rn;

        GET DIAGNOSTICS v_created_enterprise_count = ROW_COUNT;
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
        UPDATE public.%1$I dt SET
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new LU linked to a new Enterprise are initially primary
            state = %2$L
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.row_id <@ $1 -- Ensure we only update rows from the current batch
          AND dt.action = 'use'; -- Only update usable rows
    $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating _data for new enterprises and their related rows (action=insert): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing LUs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L::public.import_data_state
        WHERE dt.row_id <@ $1
          AND dt.action = 'use' AND dt.operation = 'replace'; -- Only update rows for existing LUs
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */, 'error' /* %3$L */);
     RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Updating existing LUs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_id_ranges;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_legal_unit (Batch): Finished operation. Linked % LUs to enterprises (includes new and existing).', p_job_id, v_update_count; -- v_update_count here is from the last UPDATE (skipped rows)

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_legal_unit: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
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
