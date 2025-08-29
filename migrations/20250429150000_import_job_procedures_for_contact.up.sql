-- Migration: import_job_procedures_for_contact
-- Implements the analyse and operation procedures for the Contact import step.

BEGIN;

-- Procedure to analyse contact data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_contact(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_contact$ -- Function name remains the same, step name changed
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_contact (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'contact';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found in snapshot', p_job_id;
    END IF;

    -- Single-pass update to advance priority for all non-skipped rows.
    -- This step runs for rows that might already be in an 'error' state to allow error aggregation, but it does not generate new errors.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L,
            state = 'analysing'::public.import_data_state
            -- No error column modification as this step doesn't generate errors
        WHERE dt.row_id = ANY($1) AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);

    RAISE DEBUG '[Job %] analyse_contact: Updating rows: %', p_job_id, v_sql;
    
    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_contact: Processed % rows in single pass.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_contact: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_contact_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_contact: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_contact (Batch): Finished analysis for batch. Processed % rows.', p_job_id, v_update_count;
END;
$analyse_contact$;


-- Procedure to operate (insert/update/upsert) contact data (Batch Oriented)
-- Refactored to handle temporal nature correctly using MERGE for inserts
-- and batch_insert_or_replace for replaces.
CREATE OR REPLACE PROCEDURE import.process_contact(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_contact$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition public.import_definition;
    v_step public.import_step;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_contact_count INT := 0;
    v_updated_existing_contact_count INT := 0;
    error_message TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_batch_upsert_success_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT := 'NULL::INTEGER'; 
    v_select_est_id_expr TEXT := 'NULL::INTEGER'; 
    v_select_list TEXT;
    v_update_count INT; -- Declaration for v_update_count used in propagation
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_contact (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'contact';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found in snapshot', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := v_definition.strategy;
    v_edit_by_user_id := v_job.user_id;

    v_job_mode := v_definition.mode;

    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_contact: Unhandled job mode % for unit ID selection. Expected one of (legal_unit, establishment_formal, establishment_informal).', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_contact: Based on mode %, using lu_id_expr: %, est_id_expr: % for table %', 
        p_job_id, v_job_mode, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name;

    -- Step 1: Fetch batch data into a temporary table, including action
    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER PRIMARY KEY,
        founding_row_id INTEGER, -- Added
        legal_unit_id INT,
        establishment_id INT,
        valid_after DATE, -- Added
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        web_address TEXT,
        email_address TEXT,
        phone_number TEXT,
        landline TEXT,
        mobile_number TEXT,
        fax_number TEXT,
        existing_contact_id INT, -- Will be populated later
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        action public.import_row_action_type
    ) ON COMMIT DROP;

    -- Construct the SELECT list dynamically
    v_select_list := format(
        'dt.row_id, dt.founding_row_id, %s AS legal_unit_id, %s AS establishment_id, dt.derived_valid_after, dt.derived_valid_from, dt.derived_valid_to, dt.data_source_id, dt.web_address, dt.email_address, dt.phone_number, dt.landline, dt.mobile_number, dt.fax_number, dt.edit_by_user_id, dt.edit_at, dt.edit_comment, dt.action', -- Added dt.derived_valid_after, dt.edit_comment, and dt.founding_row_id
        v_select_lu_id_expr, -- Use the correctly set expression
        v_select_est_id_expr  -- Use the correctly set expression
    );

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, legal_unit_id, establishment_id, valid_after, valid_from, valid_to, data_source_id, -- Added valid_after, founding_row_id
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            edit_by_user_id, edit_at, edit_comment, action -- Added edit_comment
        )
        SELECT %1$s
        FROM public.%2$I dt -- Alias dt is already correctly here, no change needed for this specific line.
        WHERE dt.row_id = ANY($1) AND dt.action != 'skip'
          AND ( -- Ensure at least one contact field has data
            dt.web_address IS NOT NULL OR dt.email_address IS NOT NULL OR dt.phone_number IS NOT NULL OR
            dt.landline IS NOT NULL OR dt.mobile_number IS NOT NULL OR dt.fax_number IS NOT NULL
          );
    $$, v_select_list /* %1$s */, v_data_table_name /* %2$I */);
    RAISE DEBUG '[Job %] process_contact: Fetching batch data: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 2: Determine existing contact IDs (for the specific unit, ignoring time for now)
    -- This is a simplification; batch_insert_or_replace handles the temporal lookup.
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_contact_id = c.id
        FROM public.contact c
        WHERE c.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND c.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    $$);
    RAISE DEBUG '[Job %] process_contact: Determining existing contact IDs (simplified): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created contact IDs
    CREATE TEMP TABLE temp_created_contacts (
        data_row_id INTEGER PRIMARY KEY,
        new_contact_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new contacts (action = 'insert') using MERGE
        RAISE DEBUG '[Job %] process_contact: Handling INSERTS for new contacts using MERGE.', p_job_id;

        WITH source_for_insert AS (
            SELECT * FROM temp_batch_data WHERE action = 'insert'
        ),
        merged_contacts AS (
            MERGE INTO public.contact c
            USING source_for_insert sfi
            ON 1 = 0 -- Always false to force INSERT
            WHEN NOT MATCHED THEN
                INSERT (
                    legal_unit_id, establishment_id, data_source_id,
                    web_address, email_address, phone_number, landline, mobile_number, fax_number,
                    valid_after, valid_to, edit_by_user_id, edit_at, edit_comment -- Changed
                )
                VALUES (
                    CASE WHEN v_job_mode = 'legal_unit' THEN sfi.legal_unit_id ELSE NULL END,
                    CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN sfi.establishment_id ELSE NULL END,
                    sfi.data_source_id,
                    sfi.web_address, sfi.email_address, sfi.phone_number, sfi.landline, sfi.mobile_number, sfi.fax_number,
                    sfi.valid_after, sfi.valid_to, sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment -- Use sfi.edit_comment
                )
            RETURNING c.id AS new_contact_id, sfi.data_row_id AS data_row_id
        )
        INSERT INTO temp_created_contacts (data_row_id, new_contact_id)
        SELECT data_row_id, new_contact_id
        FROM merged_contacts;

        GET DIAGNOSTICS v_inserted_new_contact_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_contact: Inserted % new contacts into temp_created_contacts via MERGE.', p_job_id, v_inserted_new_contact_count;

        IF v_inserted_new_contact_count > 0 THEN
            EXECUTE format($$
                UPDATE public.%1$I dt SET
                    contact_id = tcc.new_contact_id,
                    error = NULL,
                    state = %2$L
                FROM temp_created_contacts tcc
                WHERE dt.row_id = tcc.data_row_id AND dt.state != 'error';
            $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
            RAISE DEBUG '[Job %] process_contact: Updated _data table for % new contacts.', p_job_id, v_inserted_new_contact_count;
        END IF;

        -- Propagate newly created contact_ids to other rows in temp_batch_data
        IF v_inserted_new_contact_count > 0 THEN
            RAISE DEBUG '[Job %] process_contact: Propagating new contact_ids within temp_batch_data.', p_job_id;
            WITH new_entity_details AS (
                SELECT
                    tcc.new_contact_id,
                    tbd_founder.founding_row_id,
                    tbd_founder.legal_unit_id,
                    tbd_founder.establishment_id
                FROM temp_created_contacts tcc
                JOIN temp_batch_data tbd_founder ON tcc.data_row_id = tbd_founder.data_row_id
            )
            UPDATE temp_batch_data tbd
            SET existing_contact_id = ned.new_contact_id
            FROM new_entity_details ned
            WHERE tbd.founding_row_id = ned.founding_row_id
              AND ( -- Match on the correct unit ID based on job mode
                    (v_job_mode = 'legal_unit' AND tbd.legal_unit_id = ned.legal_unit_id AND tbd.establishment_id IS NULL AND ned.establishment_id IS NULL) OR
                    (v_job_mode IN ('establishment_formal', 'establishment_informal') AND tbd.establishment_id = ned.establishment_id AND tbd.legal_unit_id IS NULL AND ned.legal_unit_id IS NULL)
                  )
              AND tbd.existing_contact_id IS NULL -- Only update if not already set
              AND tbd.action IN ('replace', 'update'); -- Apply to subsequent actions for the same new entity
            GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-declare v_update_count or use a different local variable if needed
            RAISE DEBUG '[Job %] process_contact: Propagated new contact_ids to % rows in temp_batch_data.', p_job_id, v_update_count;
        END IF;

        -- Handle REPLACES for existing contacts (action = 'replace') using batch_insert_or_replace
        RAISE DEBUG '[Job %] process_contact: Handling REPLACES for existing contacts via batch_upsert.', p_job_id;

        CREATE TEMP TABLE temp_contact_upsert_source (
            row_id INTEGER PRIMARY KEY, 
            id INT, 
            valid_after DATE NOT NULL, -- Changed
            valid_to DATE NOT NULL,
            legal_unit_id INT,
            establishment_id INT,
            data_source_id INT,
            web_address TEXT,
            email_address TEXT,
            phone_number TEXT,
            landline TEXT,
            mobile_number TEXT,
            fax_number TEXT,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        INSERT INTO temp_contact_upsert_source (
            row_id, id, valid_after, valid_to, legal_unit_id, establishment_id, data_source_id, -- Changed valid_from to valid_after
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, -- This becomes row_id in temp_contact_upsert_source
            tbd.existing_contact_id, 
            tbd.valid_after, -- Changed
            tbd.valid_to,
            CASE WHEN v_job_mode = 'legal_unit' THEN tbd.legal_unit_id ELSE NULL END,
            CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN tbd.establishment_id ELSE NULL END,
            tbd.data_source_id,
            tbd.web_address, tbd.email_address, tbd.phone_number, tbd.landline, tbd.mobile_number, tbd.fax_number,
            tbd.edit_by_user_id,
            tbd.edit_at,
            tbd.edit_comment -- Use tbd.edit_comment
        FROM temp_batch_data tbd
        WHERE tbd.action = 'replace' AND tbd.existing_contact_id IS NOT NULL; 

        GET DIAGNOSTICS v_updated_existing_contact_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_contact: Populated temp_contact_upsert_source with % rows for batch replace.', p_job_id, v_updated_existing_contact_count;

        IF v_updated_existing_contact_count > 0 THEN
            RAISE DEBUG '[Job %] process_contact: Calling batch_insert_or_replace_generic_valid_time_table for contact.', p_job_id;
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'contact',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_contact_upsert_source',
                    p_unique_columns => '[]'::jsonb, 
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%1$I SET
                            state = %2$L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_contact_error', %3$L)
                            -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %4$L;
                    $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, v_batch_upsert_result.error_message /* %3$L */, v_batch_upsert_result.source_row_id /* %4$L */);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_contact: Batch replace finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        contact_id = tbd.existing_contact_id, -- Use the existing ID for replaces
                        error = NULL,
                        state = %2$L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id
                      AND dt.row_id = ANY($1);
                $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
                RAISE DEBUG '[Job %] process_contact: Updated _data table for % successfully replaced contacts.', p_job_id, array_length(v_batch_upsert_success_row_ids, 1);
                EXECUTE v_sql USING v_batch_upsert_success_row_ids;
            END IF;
        END IF;
        IF to_regclass('pg_temp.temp_contact_upsert_source') IS NOT NULL THEN DROP TABLE temp_contact_upsert_source; END IF;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_contact: Error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('process_contact_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_contact: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;


    -- The framework now handles advancing priority for all rows, including unprocessed and skipped rows. No update needed here.

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_contact (Batch): Finished operation in % ms. New: %, Replaced: %. Errors: %',
        p_job_id, round(v_duration_ms, 2), v_inserted_new_contact_count, v_updated_existing_contact_count, v_error_count;

    IF to_regclass('pg_temp.temp_batch_data') IS NOT NULL THEN DROP TABLE temp_batch_data; END IF;
    IF to_regclass('pg_temp.temp_created_contacts') IS NOT NULL THEN DROP TABLE temp_created_contacts; END IF;
END;
$process_contact$;


COMMIT;
