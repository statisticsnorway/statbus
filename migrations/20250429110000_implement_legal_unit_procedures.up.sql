-- Migration: implement_base_legal_unit_procedures
-- Implements the analyse and operation procedures for the legal_unit import target.

BEGIN;

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE admin.analyse_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition_snapshot JSONB; -- Renamed to avoid conflict with CONVENTIONS.md example
    v_step RECORD;
    v_row RECORD;
    v_select_sql TEXT;
    v_data_source_id INT;
    v_legal_form_id INT;
    v_status_id INT;
    v_sector_id INT;
    v_unit_size_id INT;
    v_error_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit: Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition_snapshot := v_job.definition_snapshot; -- Use the renamed variable

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found', p_job_id;
    END IF;

    v_select_sql := format($$
        SELECT
            row_id,
            NULLIF(data_source_code, '''') as data_source_code,
            NULLIF(legal_form_code, '''') as legal_form_code,
            NULLIF(status_code, '''') as status_code,
            NULLIF(sector_code, '''') as sector_code,
            NULLIF(unit_size_code, '''') as unit_size_code,
            NULLIF(birth_date, '''') as birth_date_str,
            NULLIF(death_date, '''') as death_date_str
         FROM public.%I WHERE row_id = ANY(%L)
        $$,
        v_job.data_table_name, p_batch_row_ids
    );
    RAISE DEBUG '[Job %] analyse_legal_unit: Select SQL: %', p_job_id, v_select_sql;

    FOR v_row IN EXECUTE v_select_sql
    LOOP
        BEGIN
            SELECT id INTO v_data_source_id FROM public.data_source WHERE code = v_row.data_source_code;
            SELECT id INTO v_legal_form_id FROM public.legal_form WHERE code = v_row.legal_form_code;
            SELECT id INTO v_status_id FROM public.status WHERE code = v_row.status_code;
            SELECT id INTO v_sector_id FROM public.sector WHERE code = v_row.sector_code;
            SELECT id INTO v_unit_size_id FROM public.unit_size WHERE code = v_row.unit_size_code;

            DECLARE
                v_birth_date DATE;
                v_death_date DATE;
            BEGIN
                v_birth_date := admin.safe_cast_to_date(v_row.birth_date_str);
                v_death_date := admin.safe_cast_to_date(v_row.death_date_str);

                DECLARE
                    v_update_set_parts TEXT[];
                    v_update_sql_final TEXT;
                BEGIN
                    v_update_set_parts := ARRAY[
                        format('data_source_id = %s', quote_nullable(v_data_source_id)),
                        format('legal_form_id = %s', quote_nullable(v_legal_form_id)),
                        format('status_id = %s', quote_nullable(v_status_id)),
                        format('sector_id = %s', quote_nullable(v_sector_id)),
                        format('unit_size_id = %s', quote_nullable(v_unit_size_id)),
                        format('typed_birth_date = %s', quote_nullable(v_birth_date)),
                        format('typed_death_date = %s', quote_nullable(v_death_date)),
                        format('last_completed_priority = %s', v_step.priority),
                        format('error = CASE WHEN (error - ''data_source_code'' - ''legal_form_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'' - ''conversion_lookup_error'' - ''unexpected_error'') = ''{}''::jsonb THEN NULL ELSE (error - ''data_source_code'' - ''legal_form_code'' - ''status_code'' - ''sector_code'' - ''unit_size_code'' - ''birth_date'' - ''death_date'' - ''conversion_lookup_error'' - ''unexpected_error'') END'),
                        format('state = %L', 'analysing'::public.import_data_state)
                    ];

                    v_update_sql_final := format($$UPDATE public.%I SET %s WHERE row_id = %L$$,
                        v_job.data_table_name,
                        array_to_string(v_update_set_parts, ', '),
                        v_row.row_id
                    );
                    RAISE DEBUG '[Job %] analyse_legal_unit: Update SQL for row %: %', p_job_id, v_row.row_id, v_update_sql_final;
                    EXECUTE v_update_sql_final;
                END;

            EXCEPTION WHEN others THEN
                 v_error_count := v_error_count + 1;
                 RAISE DEBUG '[Job %] analyse_legal_unit: SQLERRM for row %: %', p_job_id, v_row.row_id, SQLERRM;
                 EXECUTE format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('conversion_lookup_error', %L), last_completed_priority = %L WHERE row_id = %L$$,
                                v_job.data_table_name, 'error', SQLERRM, v_step.priority - 1, v_row.row_id);
                 RAISE DEBUG '[Job %] analyse_legal_unit: Error processing row %: %', p_job_id, v_row.row_id, SQLERRM;
            END;

        EXCEPTION WHEN others THEN
            v_error_count := v_error_count + 1;
            RAISE DEBUG '[Job %] analyse_legal_unit: SQLERRM (unexpected) for row %: %', p_job_id, v_row.row_id, SQLERRM;
            EXECUTE format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('unexpected_error', %L), last_completed_priority = %L WHERE row_id = %L$$,
                           v_job.data_table_name, 'error', 'Unexpected error: ' || SQLERRM, v_step.priority - 1, v_row.row_id);
            RAISE WARNING '[Job %] analyse_legal_unit: Unexpected error processing row %: %', p_job_id, v_row.row_id, SQLERRM;
        END;
    END LOOP;

    RAISE DEBUG '[Job %] analyse_legal_unit: Finished analysis for batch. Errors: %', p_job_id, v_error_count;

END;
$analyse_legal_unit$;


-- Procedure to operate (insert/update/upsert) base legal unit data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition_snapshot JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_lu_count INT := 0;
    v_updated_existing_lu_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_tax_ident_type_id INT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition_snapshot := v_job.definition_snapshot;
    v_data_table_name := v_job.data_table_name;

    IF v_definition_snapshot IS NULL OR jsonb_typeof(v_definition_snapshot) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target step not found', p_job_id;
    END IF;

    v_strategy := (v_definition_snapshot->'import_definition'->>'strategy')::public.import_strategy;
    IF v_strategy IS NULL THEN
        RAISE EXCEPTION '[Job %] Strategy is NULL, cannot proceed. Check definition_snapshot structure. It should be under import_definition key.', p_job_id;
    END IF;

    v_edit_by_user_id := v_job.user_id;

    SELECT id INTO v_tax_ident_type_id FROM public.external_ident_type WHERE code = 'tax_ident';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] External_ident_type for tax_ident not found.', p_job_id;
    END IF;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %, Tax Ident Type ID: %', p_job_id, v_strategy, v_edit_by_user_id, v_tax_ident_type_id;

    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    CREATE TEMP TABLE temp_batch_data (
        row_id BIGINT PRIMARY KEY,
        tax_ident TEXT,
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        legal_form_id INT,
        data_source_id INT,
        existing_lu_id INT, -- From analyse_external_idents or similar pre-step
        enterprise_id INT,
        is_primary BOOLEAN,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            row_id, tax_ident, name, typed_birth_date, typed_death_date, valid_from, valid_to,
            sector_id, unit_size_id, status_id, legal_form_id, data_source_id,
            existing_lu_id, enterprise_id, is_primary, edit_by_user_id, edit_at
        )
        SELECT
            dt.row_id,
            dt.tax_ident,
            dt.name,
            dt.typed_birth_date,
            dt.typed_death_date,
            dt.derived_valid_from as valid_from,
            dt.derived_valid_to as valid_to,
            dt.sector_id,
            dt.unit_size_id,
            dt.status_id,
            dt.legal_form_id,
            dt.data_source_id,
            dt.legal_unit_id, -- This is the existing_lu_id from _data table, populated by analyse_external_idents
            dt.enterprise_id, dt.is_primary,
            dt.edit_by_user_id, dt.edit_at
         FROM public.%I dt WHERE dt.row_id = ANY(%L);
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_legal_unit: Fetching batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created legal_unit_ids and their original data_row_id
    CREATE TEMP TABLE temp_created_lus (
        data_row_id BIGINT PRIMARY KEY,
        new_legal_unit_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new legal units (existing_lu_id IS NULL)
        IF v_strategy IN ('insert_only', 'upsert') THEN
            RAISE DEBUG '[Job %] process_legal_unit: Handling INSERTS for new LUs.', p_job_id;

            WITH rows_to_insert_lu_with_temp_key AS (
                SELECT *, row_number() OVER () as temp_insert_key
                FROM temp_batch_data
                WHERE existing_lu_id IS NULL
            ),
            inserted_legal_units AS (
                INSERT INTO public.legal_unit (
                    name, birth_date, death_date,
                    sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                    primary_for_enterprise, data_source_id, edit_by_user_id, edit_at, edit_comment
                )
                SELECT
                    rti.name, rti.typed_birth_date, rti.typed_death_date,
                    rti.sector_id, rti.unit_size_id, rti.status_id, rti.legal_form_id, rti.enterprise_id,
                    rti.is_primary, rti.data_source_id, rti.edit_by_user_id, rti.edit_at, 'Import Job Batch Insert'
                FROM rows_to_insert_lu_with_temp_key rti
                ORDER BY rti.temp_insert_key
                RETURNING id
            )
            INSERT INTO temp_created_lus (data_row_id, new_legal_unit_id)
            SELECT rtiwtk.row_id, ilu.id
            FROM rows_to_insert_lu_with_temp_key rtiwtk
            JOIN (SELECT id, row_number() OVER () as rn FROM inserted_legal_units) ilu
            ON rtiwtk.temp_insert_key = ilu.rn;

            GET DIAGNOSTICS v_inserted_new_lu_count = ROW_COUNT;
            RAISE DEBUG '[Job %] process_legal_unit: Inserted % new legal units into temp_created_lus.', p_job_id, v_inserted_new_lu_count;

            IF v_inserted_new_lu_count > 0 THEN
                INSERT INTO public.external_ident (legal_unit_id, type_id, ident, valid_from, valid_to, data_source_id, edit_by_user_id, edit_at, edit_comment)
                SELECT
                    tcl.new_legal_unit_id,
                    v_tax_ident_type_id,
                    tbd.tax_ident,
                    tbd.valid_from,
                    tbd.valid_to,
                    tbd.data_source_id,
                    tbd.edit_by_user_id,
                    tbd.edit_at,
                    'Import Job Batch Insert External Ident'
                FROM temp_created_lus tcl
                JOIN temp_batch_data tbd ON tcl.data_row_id = tbd.row_id
                WHERE tbd.tax_ident IS NOT NULL;

                RAISE DEBUG '[Job %] process_legal_unit: Inserted external idents for % new LUs.', p_job_id, v_inserted_new_lu_count;

                EXECUTE format($$
                    UPDATE public.%I dt SET
                        legal_unit_id = tcl.new_legal_unit_id,
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_created_lus tcl
                    WHERE dt.row_id = tcl.data_row_id AND dt.state != 'error';
                $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
                RAISE DEBUG '[Job %] process_legal_unit: Updated _data table for % new LUs.', p_job_id, v_inserted_new_lu_count;
            END IF;
        END IF;

        -- Handle UPDATEs/UPSERTs for existing legal units using batch_upsert_generic_valid_time_table
        IF v_strategy IN ('update_only', 'upsert') THEN
            RAISE DEBUG '[Job %] process_legal_unit: Handling UPDATES/UPSERTS for existing LUs via batch_upsert.', p_job_id;

            -- Create a temporary source table for the batch upsert function
            CREATE TEMP TABLE temp_lu_upsert_source (
                row_id BIGINT PRIMARY KEY, -- Link back to original _data row
                id INT, -- Target legal_unit ID
                valid_from DATE NOT NULL,
                valid_to DATE NOT NULL,
                name TEXT,
                birth_date DATE,
                death_date DATE,
                active BOOLEAN,
                sector_id INT,
                unit_size_id INT,
                status_id INT,
                legal_form_id INT,
                enterprise_id INT,
                primary_for_enterprise BOOLEAN,
                data_source_id INT,
                edit_by_user_id INT,
                edit_at TIMESTAMPTZ,
                edit_comment TEXT
            ) ON COMMIT DROP;

            -- Populate the temporary source table
            INSERT INTO temp_lu_upsert_source (
                row_id, id, valid_from, valid_to, name, birth_date, death_date, active,
                sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                primary_for_enterprise, data_source_id, edit_by_user_id, edit_at, edit_comment
            )
            SELECT
                tbd.row_id,
                tbd.existing_lu_id,
                tbd.valid_from,
                tbd.valid_to,
                tbd.name,
                tbd.typed_birth_date,
                tbd.typed_death_date,
                true, -- Assuming active if being updated/upserted
                tbd.sector_id,
                tbd.unit_size_id,
                tbd.status_id,
                tbd.legal_form_id,
                tbd.enterprise_id,
                tbd.is_primary,
                tbd.data_source_id,
                tbd.edit_by_user_id,
                tbd.edit_at,
                'Import Job Batch Update/Upsert'
            FROM temp_batch_data tbd
            WHERE tbd.existing_lu_id IS NOT NULL;

            GET DIAGNOSTICS v_updated_existing_lu_count = ROW_COUNT;
            RAISE DEBUG '[Job %] process_legal_unit: Populated temp_lu_upsert_source with % rows for batch upsert.', p_job_id, v_updated_existing_lu_count;

            IF v_updated_existing_lu_count > 0 THEN
                -- Call the batch upsert function
                RAISE DEBUG '[Job %] process_legal_unit: Calling batch_upsert_generic_valid_time_table for legal_unit.', p_job_id;
                FOR v_batch_upsert_result IN
                    SELECT * FROM admin.batch_upsert_generic_valid_time_table(
                        p_target_schema_name => 'public',
                        p_target_table_name => 'legal_unit',
                        p_source_schema_name => 'pg_temp', -- Assuming temp table is in pg_temp
                        p_source_table_name => 'temp_lu_upsert_source',
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
                                error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_upsert_legal_unit_error', %L),
                                last_completed_priority = %L
                            WHERE row_id = %L;
                        $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                    ELSE
                        v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                    END IF;
                END LOOP;

                v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
                RAISE DEBUG '[Job %] process_legal_unit: Batch upsert finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

                -- Ensure external_ident for successfully upserted legal units
                IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                    INSERT INTO public.external_ident (
                        legal_unit_id, type_id, ident,
                        valid_from, valid_to, data_source_id,
                        edit_by_user_id, edit_at, edit_comment
                    )
                    SELECT
                        tbd.existing_lu_id,
                        v_tax_ident_type_id,
                        tbd.tax_ident,
                        tbd.valid_from,
                        tbd.valid_to,
                        tbd.data_source_id,
                        tbd.edit_by_user_id,
                        tbd.edit_at,
                        'Import Job Batch Update/Upsert - Ensure External Ident'
                    FROM temp_batch_data tbd
                    WHERE tbd.row_id = ANY(v_batch_upsert_success_row_ids) -- Only for successful rows
                      AND tbd.existing_lu_id IS NOT NULL
                      AND tbd.tax_ident IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM public.external_ident xi
                          WHERE xi.legal_unit_id = tbd.existing_lu_id
                            AND xi.type_id = v_tax_ident_type_id
                            AND xi.ident = tbd.tax_ident
                      );
                    RAISE DEBUG '[Job %] process_legal_unit: Ensured external_ident for successfully upserted LUs.', p_job_id;

                    -- Update the _data table for successfully updated/upserted rows
                    EXECUTE format($$
                        UPDATE public.%I dt SET
                            last_completed_priority = %L,
                            error = NULL, -- Clear previous errors for this step
                            state = %L
                        WHERE dt.row_id = ANY(%L);
                    $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                    RAISE DEBUG '[Job %] process_legal_unit: Updated _data table for % successfully upserted LUs.', p_job_id, array_length(v_batch_upsert_success_row_ids, 1);
                END IF;
            END IF; -- End if v_updated_existing_lu_count > 0
            DROP TABLE IF EXISTS temp_lu_upsert_source;
        END IF; -- End if strategy allows update/upsert

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_legal_unit', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT; -- Number of rows marked as error
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_unit_error', error_message) WHERE id = p_job_id;
    END;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished. New LUs processed: %, Existing LUs processed (attempted): %. Rows marked as error in this step: %',
        p_job_id, v_inserted_new_lu_count, v_updated_existing_lu_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_lus;
END;
$process_legal_unit$;

COMMIT;
