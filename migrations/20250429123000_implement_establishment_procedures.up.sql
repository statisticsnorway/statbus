BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign separately

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for establishment
    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    -- Step 1: Batch Update Lookups
    v_sql := format('
        UPDATE public.%I dt SET
            data_source_id = src.data_source_id,
            status_id = src.status_id,
            sector_id = src.sector_id,
            unit_size_id = src.unit_size_id
        FROM (
            SELECT
                dt_sub.row_id AS row_id_for_join,
                ds.id as data_source_id,
                s.id as status_id,
                sec.id as sector_id,
                us.id as unit_size_id
            FROM public.%I dt_sub
            LEFT JOIN public.data_source ds ON dt_sub.data_source_code IS NOT NULL AND ds.code = dt_sub.data_source_code
            LEFT JOIN public.status s ON dt_sub.status_code IS NOT NULL AND s.code = dt_sub.status_code
            LEFT JOIN public.sector sec ON dt_sub.sector_code IS NOT NULL AND sec.code = dt_sub.sector_code -- Corrected join condition
            LEFT JOIN public.unit_size us ON dt_sub.unit_size_code IS NOT NULL AND us.code = dt_sub.unit_size_code
            WHERE dt_sub.row_id = ANY(%L) -- Filter for the batch
        ) AS src
        WHERE dt.row_id = src.row_id_for_join;
    ', v_data_table_name, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Batch Update Typed Dates
    v_sql := format('
        UPDATE public.%I dt SET
            typed_birth_date = admin.safe_cast_to_date(dt.birth_date),
            typed_death_date = admin.safe_cast_to_date(dt.death_date)
        WHERE dt.row_id = ANY(%L);
    ', v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating typed birth/death dates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            row_id,
            jsonb_strip_nulls(
                jsonb_build_object(''data_source_code'', CASE WHEN data_source_code IS NOT NULL AND data_source_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''status_code'', CASE WHEN status_code IS NOT NULL AND status_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''sector_code'', CASE WHEN sector_code IS NOT NULL AND sector_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''unit_size_code'', CASE WHEN unit_size_code IS NOT NULL AND unit_size_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''birth_date'', CASE WHEN birth_date IS NOT NULL AND typed_birth_date IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''death_date'', CASE WHEN death_date IS NOT NULL AND typed_death_date IS NULL THEN ''Invalid format'' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L)
    ', v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_establishment: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 4: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_establishment: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 5: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - ''data_source_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'') = ''{}''::jsonb THEN NULL ELSE (dt.error - ''data_source_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'') END,
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_establishment: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_est_count INT := 0;
    v_updated_existing_est_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_est_tax_ident_type_id INT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign separately

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for establishment
    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->'import_definition'->>'strategy')::public.import_strategy;
    IF v_strategy IS NULL THEN
        RAISE EXCEPTION '[Job %] Strategy is NULL, cannot proceed. Check definition_snapshot structure. It should be under import_definition key.', p_job_id;
    END IF;
    v_edit_by_user_id := v_job.user_id;

    -- Get ID for establishment tax identifier type
    SELECT id INTO v_est_tax_ident_type_id FROM public.external_ident_type WHERE code = 'establishment_tax_ident';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] External_ident_type for establishment_tax_ident not found.', p_job_id;
    END IF;

    RAISE DEBUG '[Job %] process_establishment: Operation Type: %, User ID: %, Est Tax Ident Type ID: %', p_job_id, v_strategy, v_edit_by_user_id, v_est_tax_ident_type_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT PRIMARY KEY,
        establishment_tax_ident TEXT,
        legal_unit_id INT, -- Populated by link_establishment_to_legal_unit step
        enterprise_id INT, -- Populated by enterprise_link_for_establishment step
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        data_source_id INT,
        existing_est_id INT, -- Populated from _data table analysis result
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, establishment_tax_ident, legal_unit_id, enterprise_id, name, typed_birth_date, typed_death_date,
            valid_from, valid_to, sector_id, unit_size_id, status_id, data_source_id,
            existing_est_id, edit_by_user_id, edit_at
        )
        SELECT
            row_id,
            establishment_tax_ident,
            legal_unit_id,
            enterprise_id,
            name,
            typed_birth_date,
            typed_death_date,
            derived_valid_from as valid_from,
            derived_valid_to as valid_to,
            sector_id,
            unit_size_id,
            status_id,
            data_source_id,
            establishment_id, -- Use the ID resolved by analyse_external_idents
            edit_by_user_id,
            edit_at
         FROM public.%I WHERE row_id = ANY(%L);
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_establishment: Fetching batch data including pre-resolved IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created establishment_ids and their original data_row_id
    CREATE TEMP TABLE temp_created_ests (
        data_row_id BIGINT PRIMARY KEY,
        new_establishment_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new establishments (existing_est_id IS NULL)
        IF v_strategy IN ('insert_only', 'upsert') THEN
            RAISE DEBUG '[Job %] process_establishment: Handling INSERTS for new ESTs.', p_job_id;

            WITH rows_to_insert_est_with_temp_key AS (
                SELECT *, row_number() OVER () as temp_insert_key
                FROM temp_batch_data
                WHERE existing_est_id IS NULL
            ),
            inserted_establishments AS (
                INSERT INTO public.establishment (
                    legal_unit_id, enterprise_id, name, birth_date, death_date,
                    sector_id, unit_size_id, status_id, data_source_id,
                    edit_by_user_id, edit_at, edit_comment
                )
                SELECT
                    rti.legal_unit_id, rti.enterprise_id, rti.name, rti.typed_birth_date, rti.typed_death_date,
                    rti.sector_id, rti.unit_size_id, rti.status_id, rti.data_source_id,
                    rti.edit_by_user_id, rti.edit_at, 'Import Job Batch Insert'
                FROM rows_to_insert_est_with_temp_key rti
                ORDER BY rti.temp_insert_key
                RETURNING id
            )
            INSERT INTO temp_created_ests (data_row_id, new_establishment_id)
            SELECT rtiwtk.data_row_id, ies.id
            FROM rows_to_insert_est_with_temp_key rtiwtk
            JOIN (SELECT id, row_number() OVER () as rn FROM inserted_establishments) ies
            ON rtiwtk.temp_insert_key = ies.rn;

            GET DIAGNOSTICS v_inserted_new_est_count = ROW_COUNT;
            RAISE DEBUG '[Job %] process_establishment: Inserted % new establishments into temp_created_ests.', p_job_id, v_inserted_new_est_count;

            IF v_inserted_new_est_count > 0 THEN
                INSERT INTO public.external_ident (establishment_id, type_id, ident, valid_from, valid_to, data_source_id, edit_by_user_id, edit_at, edit_comment)
                SELECT
                    tce.new_establishment_id,
                    v_est_tax_ident_type_id,
                    tbd.establishment_tax_ident,
                    tbd.valid_from,
                    tbd.valid_to,
                    tbd.data_source_id,
                    tbd.edit_by_user_id,
                    tbd.edit_at,
                    'Import Job Batch Insert External Ident'
                FROM temp_created_ests tce
                JOIN temp_batch_data tbd ON tce.data_row_id = tbd.data_row_id
                WHERE tbd.establishment_tax_ident IS NOT NULL;

                RAISE DEBUG '[Job %] process_establishment: Inserted external idents for % new ESTs.', p_job_id, v_inserted_new_est_count;

                EXECUTE format($$
                    UPDATE public.%I dt SET
                        establishment_id = tce.new_establishment_id,
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_created_ests tce
                    WHERE dt.row_id = tce.data_row_id AND dt.state != 'error';
                $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
                RAISE DEBUG '[Job %] process_establishment: Updated _data table for % new ESTs.', p_job_id, v_inserted_new_est_count;
            END IF;
        END IF;

        -- Handle UPDATEs/UPSERTs for existing establishments using batch_upsert_generic_valid_time_table
        IF v_strategy IN ('update_only', 'upsert') THEN
            RAISE DEBUG '[Job %] process_establishment: Handling UPDATES/UPSERTS for existing ESTs via batch_upsert.', p_job_id;

            -- Create a temporary source table for the batch upsert function
            CREATE TEMP TABLE temp_est_upsert_source (
                row_id BIGINT PRIMARY KEY, -- Link back to original _data row
                id INT, -- Target establishment ID
                valid_from DATE NOT NULL,
                valid_to DATE NOT NULL,
                legal_unit_id INT,
                enterprise_id INT,
                name TEXT,
                birth_date DATE,
                death_date DATE,
                active BOOLEAN,
                sector_id INT,
                unit_size_id INT,
                status_id INT,
                data_source_id INT,
                edit_by_user_id INT,
                edit_at TIMESTAMPTZ,
                edit_comment TEXT
            ) ON COMMIT DROP;

            -- Populate the temporary source table
            INSERT INTO temp_est_upsert_source (
                row_id, id, valid_from, valid_to, legal_unit_id, enterprise_id, name, birth_date, death_date, active,
                sector_id, unit_size_id, status_id, data_source_id, edit_by_user_id, edit_at, edit_comment
            )
            SELECT
                tbd.data_row_id,
                tbd.existing_est_id,
                tbd.valid_from,
                tbd.valid_to,
                tbd.legal_unit_id,
                tbd.enterprise_id,
                tbd.name,
                tbd.typed_birth_date,
                tbd.typed_death_date,
                true, -- Assuming active if being updated/upserted
                tbd.sector_id,
                tbd.unit_size_id,
                tbd.status_id,
                tbd.data_source_id,
                tbd.edit_by_user_id,
                tbd.edit_at,
                'Import Job Batch Update/Upsert'
            FROM temp_batch_data tbd
            WHERE tbd.existing_est_id IS NOT NULL;

            GET DIAGNOSTICS v_updated_existing_est_count = ROW_COUNT;
            RAISE DEBUG '[Job %] process_establishment: Populated temp_est_upsert_source with % rows for batch upsert.', p_job_id, v_updated_existing_est_count;

            IF v_updated_existing_est_count > 0 THEN
                -- Call the batch upsert function
                RAISE DEBUG '[Job %] process_establishment: Calling batch_upsert_generic_valid_time_table for establishment.', p_job_id;
                FOR v_batch_upsert_result IN
                    SELECT * FROM admin.batch_upsert_generic_valid_time_table(
                        p_target_schema_name => 'public',
                        p_target_table_name => 'establishment',
                        p_source_schema_name => 'pg_temp', -- Assuming temp table is in pg_temp
                        p_source_table_name => 'temp_est_upsert_source',
                        p_source_row_id_column_name => 'row_id',
                        p_unique_columns => '[]'::jsonb, -- ID is provided directly
                        p_temporal_columns => ARRAY['valid_from', 'valid_to'],
                        p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                        p_id_column_name => 'id'
                    )
                LOOP
                    IF v_batch_upsert_result.status = 'ERROR' THEN
                        v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                        -- Update the corresponding row in the _data table with the error
                        EXECUTE format($$
                            UPDATE public.%I SET
                                state = %L,
                                error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_upsert_establishment_error', %L),
                                last_completed_priority = %L
                            WHERE row_id = %L;
                        $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                    ELSE
                        v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                    END IF;
                END LOOP;

                v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
                RAISE DEBUG '[Job %] process_establishment: Batch upsert finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

                -- Ensure external_ident for successfully upserted establishments
                IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                    INSERT INTO public.external_ident (
                        establishment_id, type_id, ident,
                        valid_from, valid_to, data_source_id,
                        edit_by_user_id, edit_at, edit_comment
                    )
                    SELECT
                        tbd.existing_est_id,
                        v_est_tax_ident_type_id,
                        tbd.establishment_tax_ident,
                        tbd.valid_from,
                        tbd.valid_to,
                        tbd.data_source_id,
                        tbd.edit_by_user_id,
                        tbd.edit_at,
                        'Import Job Batch Update/Upsert - Ensure External Ident'
                    FROM temp_batch_data tbd
                    WHERE tbd.data_row_id = ANY(v_batch_upsert_success_row_ids) -- Only for successful rows
                      AND tbd.existing_est_id IS NOT NULL
                      AND tbd.establishment_tax_ident IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM public.external_ident xi
                          WHERE xi.establishment_id = tbd.existing_est_id
                            AND xi.type_id = v_est_tax_ident_type_id
                            AND xi.ident = tbd.establishment_tax_ident
                      );
                    RAISE DEBUG '[Job %] process_establishment: Ensured external_ident for successfully upserted ESTs.', p_job_id;

                    -- Update the _data table for successfully updated/upserted rows
                    EXECUTE format($$
                        UPDATE public.%I dt SET
                            establishment_id = tbd.existing_est_id, -- Confirm the ID
                            last_completed_priority = %L,
                            error = NULL, -- Clear previous errors for this step
                            state = %L
                        FROM temp_batch_data tbd -- Join to get existing_est_id
                        WHERE dt.row_id = tbd.data_row_id
                          AND dt.row_id = ANY(%L);
                    $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                    RAISE DEBUG '[Job %] process_establishment: Updated _data table for % successfully upserted ESTs.', p_job_id, array_length(v_batch_upsert_success_row_ids, 1);
                END IF;
            END IF; -- End if v_updated_existing_est_count > 0
            DROP TABLE IF EXISTS temp_est_upsert_source;
        END IF; -- End if strategy allows update/upsert

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Error during batch operation: %', p_job_id, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_establishment', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT; -- Number of rows marked as error
        UPDATE public.import_job SET error = jsonb_build_object('process_establishment_error', error_message) WHERE id = p_job_id;
    END;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_establishment (Batch): Finished. New ESTs processed: %, Existing ESTs processed (attempted): %. Rows marked as error in this step: %',
        p_job_id, v_inserted_new_est_count, v_updated_existing_est_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_ests;
END;
$process_establishment$;

END;
