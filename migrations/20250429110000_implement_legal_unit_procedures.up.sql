-- Migration: implement_base_legal_unit_procedures
-- Implements the analyse and operation procedures for the legal_unit import target.

BEGIN;

-- Procedure to analyse base legal unit data
CREATE OR REPLACE PROCEDURE admin.analyse_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_legal_unit$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
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
    v_definition := v_job.definition_snapshot;

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target not found', p_job_id;
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
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_legal_unit (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot;
    v_data_table_name := v_job.data_table_name;

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target not found', p_job_id;
    END IF;

    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    RAISE DEBUG '[Job %] process_legal_unit: Operation Type: %, User ID: %', p_job_id, v_strategy, v_edit_by_user_id;

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
        existing_lu_id INT,
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
            row_id,
            tax_ident,
            name,
            typed_birth_date,
            typed_death_date,
            derived_valid_from as valid_from,
            derived_valid_to as valid_to,
            sector_id,
            unit_size_id,
            status_id,
            legal_form_id,
            data_source_id,
            legal_unit_id, -- This is the existing_lu_id from _data table
            enterprise_id, is_primary,
            edit_by_user_id, edit_at
         FROM public.%I WHERE row_id = ANY(%L);
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_legal_unit: Fetching batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    CREATE TEMP TABLE temp_inserted_lu_ids (
        row_id BIGINT PRIMARY KEY,
        legal_unit_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        v_sql := format($$
            WITH data_to_insert AS (
                SELECT
                    tbd.row_id,
                    tbd.existing_lu_id,
                    tbd.valid_from, tbd.valid_to, tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true as active, 'Import Job Batch' as edit_comment,
                    tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.legal_form_id, tbd.enterprise_id,
                    tbd.is_primary, tbd.data_source_id, tbd.edit_by_user_id, tbd.edit_at
                FROM temp_batch_data tbd
                WHERE
                    CASE %L::public.import_strategy
                        WHEN 'insert_only' THEN tbd.existing_lu_id IS NULL
                        WHEN 'update_only' THEN tbd.existing_lu_id IS NOT NULL
                        WHEN 'upsert' THEN TRUE
                    END
            ), inserted_eras AS (
                INSERT INTO public.legal_unit_era (
                    id, valid_from, valid_to, name, birth_date, death_date, active, edit_comment,
                    sector_id, unit_size_id, status_id, legal_form_id, enterprise_id,
                    primary_for_enterprise, data_source_id, edit_by_user_id, edit_at
                )
                SELECT
                    dti.existing_lu_id,
                    dti.valid_from, dti.valid_to, dti.name, dti.typed_birth_date, dti.typed_death_date, dti.active, dti.edit_comment,
                    dti.sector_id, dti.unit_size_id, dti.status_id, dti.legal_form_id, dti.enterprise_id,
                    dti.is_primary, dti.data_source_id, dti.edit_by_user_id, dti.edit_at
                FROM data_to_insert dti
                RETURNING id
            )
            INSERT INTO temp_inserted_lu_ids (row_id, legal_unit_id)
            SELECT dti.row_id, ie.id
            FROM data_to_insert dti
            JOIN inserted_eras ie ON TRUE;
        $$, v_strategy);

        RAISE DEBUG '[Job %] process_legal_unit: Performing batch INSERT into legal_unit_era and capturing IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;

        v_sql := format($$
            UPDATE public.%I dt SET
                legal_unit_id = til.legal_unit_id,
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_inserted_lu_ids til
            WHERE dt.row_id = til.row_id
              AND dt.state != %L;
        $$, v_data_table_name, v_step.priority, 'processing', 'error');
        RAISE DEBUG '[Job %] process_legal_unit: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_unit: Error during batch operation: %', p_job_id, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_unit_error', error_message) WHERE id = p_job_id;
    END;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_legal_unit (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_row_ids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_inserted_lu_ids;
END;
$process_legal_unit$;

COMMIT;
