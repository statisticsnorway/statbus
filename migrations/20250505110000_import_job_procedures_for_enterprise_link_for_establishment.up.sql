-- Migration: import_job_procedures_for_enterprise_link_for_establishment
-- Implements the analyse and process procedures for the enterprise_link_for_establishment import step.

BEGIN;

-- Procedure to analyse enterprise link for standalone establishments
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_enterprise_link_for_establishment$
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
    v_error_keys_to_clear_arr TEXT[];
    v_external_ident_source_column_names_json JSONB;
    v_external_ident_source_columns TEXT[];
BEGIN
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Starting analysis for % rows. Batch Row IDs: %', p_job_id, array_length(p_batch_row_ids, 1), p_batch_row_ids;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

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
        -- Fallback if no specific columns are found
        v_external_ident_source_columns := ARRAY['tax_ident']; -- Sensible default
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: No source_input columns found for external_idents step. Falling back to: %', p_job_id, v_external_ident_source_columns;
    ELSE
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Identified external_idents source_input columns: %', p_job_id, v_external_ident_source_columns;
    END IF;
    v_error_keys_to_clear_arr := v_external_ident_source_columns;

    -- Find the step details from the snapshot first
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''.', p_job_id, v_job_mode;
        EXECUTE format($$UPDATE public.%1$I SET last_completed_priority = %2$L WHERE row_id = ANY($1)$$, 
                       v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        RETURN;
    END IF;

    -- For 'replace' actions in 'establishment_informal' mode, attempt to find the existing establishment
    -- and its enterprise. If not found, or if enterprise_id is NULL, it's a fatal error.
    v_sql := format($$
        WITH est_data AS (
            SELECT dt.row_id, est.enterprise_id AS existing_enterprise_id, est.primary_for_enterprise AS existing_primary_for_enterprise, est.id as found_est_id
            FROM public.%1$I dt -- v_data_table_name
            LEFT JOIN public.establishment est ON dt.establishment_id = est.id
            WHERE dt.row_id = ANY($1) AND dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' -- v_job_mode
        )
        UPDATE public.%1$I dt SET -- v_data_table_name
            enterprise_id = CASE
                                WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_enterprise_id -- v_job_mode
                                ELSE dt.enterprise_id
                            END,
            primary_for_enterprise = CASE
                                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL THEN ed.existing_primary_for_enterprise -- v_job_mode
                                        ELSE dt.primary_for_enterprise
                                     END,
            state = CASE
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NULL THEN 'error'::public.import_data_state -- EST not found -- v_job_mode
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN 'error'::public.import_data_state -- EST found but no enterprise_id (inconsistent for informal) -- v_job_mode
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NULL THEN -- v_job_mode
                            COALESCE(dt.error, '{}'::jsonb) || (SELECT jsonb_object_agg(col_name, 'Establishment identified by external identifier was not found for ''replace'' action.') FROM unnest(%5$L::TEXT[]) as col_name)
                        WHEN dt.action = 'replace' AND dt.establishment_id IS NOT NULL AND %2$L = 'establishment_informal' AND ed.found_est_id IS NOT NULL AND ed.existing_enterprise_id IS NULL THEN -- v_job_mode
                            COALESCE(dt.error, '{}'::jsonb) || (SELECT jsonb_object_agg(col_name, 'Informal establishment found for ''replace'' action, but it is not linked to an enterprise.') FROM unnest(%5$L::TEXT[]) as col_name)
                        ELSE CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END -- v_error_keys_to_clear_arr
                    END,
            last_completed_priority = %4$L -- Always v_step.priority
        FROM public.%1$I dt_main -- Alias for the main table being updated -- v_data_table_name
        LEFT JOIN est_data ed ON dt_main.row_id = ed.row_id
        WHERE dt.row_id = dt_main.row_id
          AND dt_main.row_id = ANY($1) AND dt_main.action = 'replace' AND %2$L = 'establishment_informal'; -- v_job_mode
    $$,
        v_data_table_name,          -- %1$I
        v_job_mode,                 -- %2$L
        v_error_keys_to_clear_arr,  -- %3$L
        v_step.priority,            -- %4$L (always this step's priority)
        v_external_ident_source_columns -- %5$L
    );

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updating "replace" rows for informal establishments: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_processed_non_skip_count = ROW_COUNT; -- This counts rows updated by the above SQL (action='replace' and mode='establishment_informal')
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Processed % "replace" rows for informal establishments (includes potential errors).', p_job_id, v_processed_non_skip_count;

        -- Update priority for 'insert' and 'skip' rows, and 'replace' rows not matching the first UPDATE's criteria (e.g. not informal, or establishment_id was NULL)
        v_sql := format($$
            UPDATE public.%1$I dt SET -- v_data_table_name
                last_completed_priority = %2$s, -- v_step.priority
                state = 'analysing'::public.import_data_state,
                error = CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END -- v_error_keys_to_clear_arr
            WHERE dt.row_id = ANY($1) -- p_batch_row_ids
              AND (dt.action = 'insert' OR dt.action = 'skip' OR (dt.action = 'replace' AND dt.last_completed_priority < %2$s)); -- v_step.priority
        $$,
            v_data_table_name,              -- %1$I
            v_step.priority,                -- %2$s
            v_error_keys_to_clear_arr,      -- %3$L
            p_batch_row_ids                 -- $1
        );
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Updated priority/state for % other rows.', p_job_id, v_update_count;
        v_update_count := v_processed_non_skip_count + v_update_count; -- Total rows touched

    EXCEPTION WHEN OTHERS THEN
        error_message := SQLERRM;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_establishment: Error during batch update: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_establishment_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, 'analyse_enterprise_link_for_establishment');

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (Batch): Finished analysis successfully.', p_job_id;
END;
$analyse_enterprise_link_for_establishment$;


-- Procedure to process enterprise link for standalone establishments (create enterprise for new ESTs)
CREATE OR REPLACE PROCEDURE import.process_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_enterprise_link_for_establishment$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_created_enterprise_count INT := 0;
    error_message TEXT;
    rec_new_est RECORD;
    new_enterprise_id INT;
    v_job_mode public.import_mode;
BEGIN
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Find the step details from the snapshot first
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'enterprise_link_for_establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] enterprise_link_for_establishment step not found in snapshot', p_job_id; END IF;

    IF v_job_mode != 'establishment_informal' THEN
        RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Skipping, job mode is %, not ''establishment_informal''. No action needed.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Step 1: Identify rows needing enterprise creation (new standalone ESTs, action = 'insert')
    CREATE TEMP TABLE temp_new_est_for_enterprise_creation (
        data_row_id INTEGER PRIMARY KEY, -- This will be the founding_row_id for the new EST entity
        est_name TEXT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_new_est_for_enterprise_creation (data_row_id, est_name, edit_by_user_id, edit_at, edit_comment)
        SELECT dt.row_id, dt.name, dt.edit_by_user_id, dt.edit_at, dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.row_id = ANY($1) AND dt.action = 'insert' AND dt.founding_row_id = dt.row_id; -- Only process founding rows for new ESTs
    $$, v_data_table_name /* %1$I */);
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 2: Create new enterprises for ESTs in temp_new_est_for_enterprise_creation and map them
    -- temp_created_enterprises.data_row_id will store the founding_row_id of the EST
    CREATE TEMP TABLE temp_created_enterprises (
        data_row_id INTEGER PRIMARY KEY, -- Stores the founding_row_id of the EST
        enterprise_id INT NOT NULL
    ) ON COMMIT DROP;

    v_created_enterprise_count := 0;
    BEGIN
        FOR rec_new_est IN SELECT * FROM temp_new_est_for_enterprise_creation LOOP
            INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at, edit_comment)
            VALUES (NULL, rec_new_est.edit_by_user_id, rec_new_est.edit_at, rec_new_est.edit_comment) -- Set short_name to NULL
            RETURNING id INTO new_enterprise_id;

            INSERT INTO temp_created_enterprises (data_row_id, enterprise_id)
            VALUES (rec_new_est.data_row_id, new_enterprise_id);
            v_created_enterprise_count := v_created_enterprise_count + 1;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Programming error suspected during enterprise creation loop: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job SET error = jsonb_build_object('programming_error_process_enterprise_link_est', error_message) WHERE id = p_job_id;
        -- Constraints and temp table cleanup will be handled by the main exception block or successful completion
        RAISE;
    END;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Created % new enterprises.', p_job_id, v_created_enterprise_count;

    -- Step 3: Update _data table for newly created enterprises (action = 'insert') and their related 'replace' rows
    -- For new informal ESTs linked to new Enterprises, all their initial slices are primary.
    v_sql := format($$
        UPDATE public.%1$I dt SET -- v_data_table_name
            enterprise_id = tce.enterprise_id,
            primary_for_enterprise = TRUE, -- All slices of a new informal EST linked to a new Enterprise are initially primary
            error = NULL,
            state = %2$L -- 'processing'
        FROM temp_created_enterprises tce -- tce.data_row_id is the founding_row_id
        WHERE dt.founding_row_id = tce.data_row_id -- Link all rows of the entity via founding_row_id
          AND dt.row_id = ANY($1) -- p_batch_row_ids
          AND dt.state != 'error'; -- Avoid updating rows already in error from a prior step
    $$, v_data_table_name, 'processing'::public.import_data_state);
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating _data for new enterprises and their related rows: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    -- Step 4: Update rows that were already processed by analyse step (existing ESTs, action = 'replace') - just advance priority
    v_sql := format($$
        UPDATE public.%1$I dt SET
            state = %2$L
        WHERE dt.row_id = ANY($1)
          AND dt.action = 'replace' -- Only update rows for existing ESTs (mode 'establishment_informal' implies no LU link in data)
          AND dt.state != %3$L; -- Avoid rows already in error
    $$, v_data_table_name /* %1$I */, 'processing' /* %2$L */, 'error' /* %3$L */);
     RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Updating existing ESTs (action=replace, priority only): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 5: Update skipped rows (action = 'skip') - no LCP update needed in processing phase.
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-using v_update_count, fine for debug
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment (Batch): Finished operation. Created % enterprises.', p_job_id, v_created_enterprise_count;

    DROP TABLE IF EXISTS temp_new_est_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    RAISE WARNING '[Job %] process_enterprise_link_for_establishment: Unhandled error during operation: %', p_job_id, replace(error_message, '%', '%%');
    -- Ensure cleanup even on unexpected error
    DROP TABLE IF EXISTS temp_new_est_for_enterprise_creation;
    DROP TABLE IF EXISTS temp_created_enterprises;
    -- Update job error
    UPDATE public.import_job
    SET error = jsonb_build_object('process_enterprise_link_for_establishment_error', error_message),
        state = 'finished'
    WHERE id = p_job_id;
    RAISE DEBUG '[Job %] process_enterprise_link_for_establishment: Marked job as failed due to error: %', p_job_id, error_message;
    RAISE; -- Re-raise the original exception
END;
$process_enterprise_link_for_establishment$;

COMMIT;
