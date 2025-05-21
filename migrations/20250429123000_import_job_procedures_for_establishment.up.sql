BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['data_source_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date', 'status_id_missing'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['data_source_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get default status_id -- Removed
    -- SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    -- RAISE DEBUG '[Job %] analyse_establishment: Default status_id found: %', p_job_id, v_default_status_id;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; 
    v_data_table_name := v_job.data_table_name; 

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id as data_row_id,
                ds.id as resolved_data_source_id,
                -- s.id as resolved_status_id, -- Removed status lookup
                sec.id as resolved_sector_id,
                us.id as resolved_unit_size_id,
                import.safe_cast_to_date(dt_sub.birth_date) as resolved_typed_birth_date,
                import.safe_cast_to_date(dt_sub.death_date) as resolved_typed_death_date
            FROM public.%I dt_sub
            LEFT JOIN public.data_source_available ds ON NULLIF(dt_sub.data_source_code, '') IS NOT NULL AND ds.code = NULLIF(dt_sub.data_source_code, '')
            -- LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = NULLIF(dt_sub.status_code, '') AND s.active = true -- Removed
            LEFT JOIN public.sector_available sec ON NULLIF(dt_sub.sector_code, '') IS NOT NULL AND sec.code = NULLIF(dt_sub.sector_code, '')
            LEFT JOIN public.unit_size_available us ON NULLIF(dt_sub.unit_size_code, '') IS NOT NULL AND us.code = NULLIF(dt_sub.unit_size_code, '')
            WHERE dt_sub.row_id = ANY(%L) AND dt_sub.action != 'skip' -- Exclude skipped rows
        )
        UPDATE public.%I dt SET
            data_source_id = l.resolved_data_source_id,
            -- status_id = CASE ... END, -- Removed: status_id is now populated by 'status' step
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            typed_birth_date = l.resolved_typed_birth_date,
            typed_death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN dt.status_id IS NULL THEN 'error'::public.import_data_state -- Fatal if status_id is missing
                        ELSE 'analysing'::public.import_data_state -- Non-fatal for other issues
                    END,
            error = CASE
                        WHEN dt.status_id IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('status_id_missing', 'Status ID not resolved by prior step')
                        ELSE -- Clear specific non-fatal error keys if they were previously set
                            CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            invalid_codes = CASE
                                WHEN dt.status_id IS NOT NULL THEN -- Only populate invalid_codes if status_id is present
                                    jsonb_strip_nulls(
                                     COALESCE(dt.invalid_codes, '{}'::jsonb) - %L::TEXT[] || -- Remove old keys first
                                     jsonb_build_object('data_source_code', CASE WHEN NULLIF(dt.data_source_code, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code', CASE WHEN NULLIF(dt.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN dt.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code', CASE WHEN NULLIF(dt.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN dt.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date', CASE WHEN NULLIF(dt.birth_date, '') IS NOT NULL AND l.resolved_typed_birth_date IS NULL THEN dt.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date', CASE WHEN NULLIF(dt.death_date, '') IS NOT NULL AND l.resolved_typed_death_date IS NULL THEN dt.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes -- Keep existing invalid_codes if it's a fatal status_id error
                            END,
            last_completed_priority = CASE
                                        WHEN dt.status_id IS NULL THEN dt.last_completed_priority -- Fatal: Preserve existing LCP
                                        ELSE %s -- Non-fatal or success: v_step.priority
                                      END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.row_id = ANY(%L) AND dt.action != 'skip'; -- Ensure main update also excludes skipped
    $$,
        v_job.data_table_name, p_batch_row_ids,                     -- For lookups CTE
        v_job.data_table_name,                                      -- For main UPDATE target
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,       -- For error CASE (clear)
        v_invalid_code_keys_arr,                                    -- For invalid_codes CASE (clear old)
        v_step.priority,                                            -- For last_completed_priority CASE (success part)
        p_batch_row_ids                                             -- For final WHERE clause
    );

    RAISE DEBUG '[Job %] analyse_establishment: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
        ', v_data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_job.data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_establishment: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_establishment_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_establishment: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
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
    error_message TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    -- Removed v_has_*_col flags, will use v_job_mode
    v_select_enterprise_id_expr TEXT := 'NULL::INTEGER';
    v_select_legal_unit_id_expr TEXT := 'NULL::INTEGER';
    v_select_primary_for_legal_unit_expr TEXT := 'NULL::BOOLEAN';
    v_select_primary_for_enterprise_expr TEXT := 'NULL::BOOLEAN';
    rec_created_est RECORD;
    rec_ident_type public.external_ident_type_active;
    v_ident_value TEXT;
    sample_data_row RECORD;
    v_data_table_col_name TEXT;
    v_select_list TEXT;
    v_job_mode public.import_mode; -- Added for job mode
BEGIN
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot;
    v_data_table_name := v_job.data_table_name;

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    v_job_mode := (v_definition->'import_definition'->>'mode')::public.import_mode;
    IF v_job_mode IS NULL OR v_job_mode NOT IN ('establishment_formal', 'establishment_informal') THEN
        RAISE EXCEPTION '[Job %] Invalid or missing mode for establishment processing: %. Expected ''establishment_formal'' or ''establishment_informal''.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_establishment: Job mode is %', p_job_id, v_job_mode;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    v_strategy := (v_definition->'import_definition'->>'strategy')::public.import_strategy;
    IF v_strategy IS NULL THEN
        RAISE EXCEPTION '[Job %] Strategy is NULL, cannot proceed. Check definition_snapshot structure.', p_job_id;
    END IF;
    v_edit_by_user_id := v_job.user_id;
    RAISE DEBUG '[Job %] process_establishment: Operation Type: %, User ID: %', p_job_id, v_strategy, v_edit_by_user_id;

    -- Determine select expressions based on job mode
    IF v_job_mode = 'establishment_formal' THEN
        v_select_legal_unit_id_expr := 'dt.legal_unit_id';
        v_select_primary_for_legal_unit_expr := 'dt.primary_for_legal_unit';
        -- enterprise_id and primary_for_enterprise remain NULL for formal establishments
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_enterprise_id_expr := 'dt.enterprise_id';
        v_select_primary_for_enterprise_expr := 'dt.primary_for_enterprise';
        -- legal_unit_id and primary_for_legal_unit remain NULL for informal establishments
    END IF;

    RAISE DEBUG '[Job %] process_establishment: Based on mode % - Dynamic select expressions for table %: legal_unit_id_expr=%, primary_for_legal_unit_expr=%, enterprise_id_expr=%, primary_for_enterprise_expr=%',
        p_job_id, v_job_mode, v_data_table_name, v_select_legal_unit_id_expr, v_select_primary_for_legal_unit_expr, v_select_enterprise_id_expr, v_select_primary_for_enterprise_expr;

    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT PRIMARY KEY,
        tax_ident TEXT,
        legal_unit_id INT,
        primary_for_legal_unit BOOLEAN,
        enterprise_id INT,
        primary_for_enterprise BOOLEAN, -- Added
        name TEXT,
        typed_birth_date DATE,
        typed_death_date DATE,
        valid_after DATE, -- Added to source from derived_valid_after
        valid_from DATE,
        valid_to DATE,
        sector_id INT,
        unit_size_id INT,
        status_id INT,
        data_source_id INT,
        existing_est_id INT,
        invalid_codes JSONB, -- Added
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        action public.import_row_action_type
    ) ON COMMIT DROP;

    v_select_list := format(
        'dt.row_id, dt.tax_ident, %s AS legal_unit_id, %s AS primary_for_legal_unit, %s AS enterprise_id, %s AS primary_for_enterprise, dt.name, dt.typed_birth_date, dt.typed_death_date, dt.derived_valid_after, dt.derived_valid_from, dt.derived_valid_to, dt.sector_id, dt.unit_size_id, dt.status_id, dt.data_source_id, dt.establishment_id, dt.invalid_codes, dt.edit_by_user_id, dt.edit_at, dt.edit_comment, dt.action',
        v_select_legal_unit_id_expr,
        v_select_primary_for_legal_unit_expr,
        v_select_enterprise_id_expr,
        v_select_primary_for_enterprise_expr
    );

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, tax_ident, legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, typed_birth_date, typed_death_date,
            valid_after, valid_from, valid_to, sector_id, unit_size_id, status_id, data_source_id,
            existing_est_id, invalid_codes, edit_by_user_id, edit_at, edit_comment, action
        )
        SELECT %s
         FROM public.%I dt WHERE dt.row_id = ANY(%L) AND dt.action != 'skip';
    $$, v_select_list, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_establishment: Fetching batch data (including invalid_codes): %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Log sample data from temp_batch_data after initial population
    FOR sample_data_row IN SELECT * FROM temp_batch_data LIMIT 5 LOOP
        RAISE DEBUG '[Job %] process_establishment: Sample temp_batch_data after fetch: data_row_id=%, tax_ident=%, legal_unit_id=%, pflu=%, enterprise_id=%, pfe=%, name=%, action=%',
                     p_job_id, sample_data_row.data_row_id, sample_data_row.tax_ident, sample_data_row.legal_unit_id, sample_data_row.primary_for_legal_unit, sample_data_row.enterprise_id, sample_data_row.primary_for_enterprise, sample_data_row.name, sample_data_row.action;
    END LOOP;

    -- The enterprise_id is populated by import.analyse_enterprise_link_for_establishment if that step is included.
    -- It should not be looked up directly here from legal_unit.

    CREATE TEMP TABLE temp_created_ests (
        data_row_id BIGINT PRIMARY KEY,
        new_establishment_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        RAISE DEBUG '[Job %] process_establishment: Handling INSERTS for new ESTs using MERGE.', p_job_id;

        -- Log data going into MERGE for inserts
        FOR sample_data_row IN SELECT * FROM temp_batch_data WHERE action = 'insert' LIMIT 5 LOOP
            RAISE DEBUG '[Job %] process_establishment: MERGE INSERT source: data_row_id=%, legal_unit_id=%, pflu=%, enterprise_id=%, pfe=%, name=%',
                         p_job_id, sample_data_row.data_row_id, sample_data_row.legal_unit_id, sample_data_row.primary_for_legal_unit, sample_data_row.enterprise_id, sample_data_row.primary_for_enterprise, sample_data_row.name;
        END LOOP;

        WITH source_for_insert AS (
            SELECT * FROM temp_batch_data WHERE action = 'insert'
        ),
        merged_establishments AS (
            MERGE INTO public.establishment est
            USING source_for_insert sfi
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (
                    legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, birth_date, death_date,
                    sector_id, unit_size_id, status_id, data_source_id, invalid_codes, -- Added invalid_codes
                    valid_from, valid_to,
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    sfi.legal_unit_id, -- Will be NULL if mode is informal, based on prior select into temp_batch_data
                    sfi.primary_for_legal_unit, -- Will be NULL if mode is informal
                    sfi.enterprise_id, -- Will be NULL if mode is formal
                    sfi.primary_for_enterprise, -- Will be NULL if mode is formal
                    sfi.name, sfi.typed_birth_date, sfi.typed_death_date,
                    sfi.sector_id, sfi.unit_size_id, sfi.status_id, sfi.data_source_id, sfi.invalid_codes, -- Added sfi.invalid_codes
                    sfi.valid_from, sfi.valid_to,
                    sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment
                )
            RETURNING est.id AS new_establishment_id, sfi.data_row_id
        )
        INSERT INTO temp_created_ests (data_row_id, new_establishment_id)
        SELECT data_row_id, new_establishment_id
        FROM merged_establishments;

        GET DIAGNOSTICS v_inserted_new_est_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_establishment: Inserted % new establishments into temp_created_ests via MERGE.', p_job_id, v_inserted_new_est_count;

        IF v_inserted_new_est_count > 0 THEN
            FOR rec_created_est IN SELECT tce.data_row_id, tce.new_establishment_id, tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment
                                   FROM temp_created_ests tce
                                   JOIN temp_batch_data tbd ON tce.data_row_id = tbd.data_row_id 
            LOOP
                FOR rec_ident_type IN SELECT * FROM public.external_ident_type_active ORDER BY priority LOOP
                    v_data_table_col_name := rec_ident_type.code;
                    BEGIN
                        EXECUTE format('SELECT %I FROM public.%I WHERE row_id = %L',
                                       v_data_table_col_name, v_data_table_name, rec_created_est.data_row_id)
                        INTO v_ident_value;

                        IF v_ident_value IS NOT NULL AND v_ident_value <> '' THEN
                            RAISE DEBUG '[Job %] process_establishment: For new EST (id: %), data_row_id: %, ident_type: % (code: %), value: %',
                                        p_job_id, rec_created_est.new_establishment_id, rec_created_est.data_row_id, rec_ident_type.id, rec_ident_type.code, v_ident_value;
                            INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                            VALUES (rec_created_est.new_establishment_id, rec_ident_type.id, v_ident_value, rec_created_est.edit_by_user_id, rec_created_est.edit_at, rec_created_est.edit_comment)
                            ON CONFLICT (type_id, ident) DO UPDATE SET
                                establishment_id    = EXCLUDED.establishment_id,
                                legal_unit_id       = NULL,
                                enterprise_id       = NULL,
                                enterprise_group_id = NULL,
                                edit_by_user_id     = EXCLUDED.edit_by_user_id,
                                edit_at             = EXCLUDED.edit_at,
                                edit_comment        = EXCLUDED.edit_comment;
                        END IF;
                    EXCEPTION
                        WHEN undefined_column THEN
                             RAISE DEBUG '[Job %] process_establishment: Column % for ident type % not found in % for data_row_id %, skipping this ident type for this row.',
                                        p_job_id, v_data_table_col_name, rec_ident_type.code, v_data_table_name, rec_created_est.data_row_id;
                    END;
                END LOOP;
            END LOOP;
            RAISE DEBUG '[Job %] process_establishment: Processed external idents for % new ESTs.', p_job_id, v_inserted_new_est_count;


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

        RAISE DEBUG '[Job %] process_establishment: Handling REPLACES for existing ESTs via batch_upsert.', p_job_id;

        CREATE TEMP TABLE temp_est_upsert_source (
            data_row_id BIGINT PRIMARY KEY,
            id INT,
            valid_after DATE NOT NULL,
            valid_to DATE NOT NULL,
            legal_unit_id INT,
            primary_for_legal_unit BOOLEAN,
            enterprise_id INT,
            primary_for_enterprise BOOLEAN, -- Added
            name TEXT,
            birth_date DATE,
            death_date DATE,
            active BOOLEAN,
            sector_id INT,
            unit_size_id INT,
            status_id INT,
            data_source_id INT,
            invalid_codes JSONB, -- Added
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        INSERT INTO temp_est_upsert_source (
            data_row_id, id, valid_after, valid_to, legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, birth_date, death_date, active,
            sector_id, unit_size_id, status_id, data_source_id, invalid_codes, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, tbd.existing_est_id, tbd.valid_after, tbd.valid_to, -- Use tbd.valid_after directly
            tbd.legal_unit_id, -- Value from temp_batch_data, correctly nulled by mode if needed
            tbd.primary_for_legal_unit, -- Value from temp_batch_data
            tbd.enterprise_id, -- Value from temp_batch_data
            tbd.primary_for_enterprise, -- Value from temp_batch_data
            tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true,
            tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.data_source_id,
            tbd.invalid_codes, -- Added
            tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment
        FROM temp_batch_data tbd
        WHERE tbd.action = 'replace';

        GET DIAGNOSTICS v_updated_existing_est_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_establishment: Populated temp_est_upsert_source with % rows for batch replace.', p_job_id, v_updated_existing_est_count;

        IF v_updated_existing_est_count > 0 THEN
            RAISE DEBUG '[Job %] process_establishment: Calling batch_insert_or_replace_generic_valid_time_table for establishment.', p_job_id;
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public', p_target_table_name => 'establishment',
                    p_source_schema_name => 'pg_temp', p_source_table_name => 'temp_est_upsert_source',
                    p_source_row_id_column_name => 'data_row_id', p_unique_columns => '[]'::jsonb,
                    p_temporal_columns => ARRAY['valid_after', 'valid_to'],
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_establishment_error', %L)
                        -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_establishment: Batch replace finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                FOR rec_created_est IN SELECT tbd.data_row_id, tbd.existing_est_id as new_establishment_id, tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment
                                       FROM temp_batch_data tbd
                                       WHERE tbd.data_row_id = ANY(v_batch_upsert_success_row_ids)
                LOOP
                    FOR rec_ident_type IN SELECT * FROM public.external_ident_type_active ORDER BY priority LOOP
                        v_data_table_col_name := rec_ident_type.code;
                        BEGIN
                            EXECUTE format('SELECT %I FROM public.%I WHERE row_id = %L',
                                           v_data_table_col_name, v_data_table_name, rec_created_est.data_row_id)
                            INTO v_ident_value;

                            IF v_ident_value IS NOT NULL AND v_ident_value <> '' THEN
                                RAISE DEBUG '[Job %] process_establishment: For existing EST (id: %), data_row_id: %, ident_type: % (code: %), value: %',
                                            p_job_id, rec_created_est.new_establishment_id, rec_created_est.data_row_id, rec_ident_type.id, rec_ident_type.code, v_ident_value;
                                INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                                VALUES (rec_created_est.new_establishment_id, rec_ident_type.id, v_ident_value, rec_created_est.edit_by_user_id, rec_created_est.edit_at, rec_created_est.edit_comment)
                                ON CONFLICT (type_id, ident) DO UPDATE SET
                                    establishment_id = EXCLUDED.establishment_id, legal_unit_id = NULL, enterprise_id = NULL, enterprise_group_id = NULL,
                                    edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at, edit_comment = EXCLUDED.edit_comment;
                            END IF;
                        EXCEPTION
                            WHEN undefined_column THEN
                                RAISE DEBUG '[Job %] process_establishment: Column % for ident type % not found in % for data_row_id %, skipping this ident type for this row.',
                                            p_job_id, v_data_table_col_name, rec_ident_type.code, v_data_table_name, rec_created_est.data_row_id;
                        END;
                    END LOOP;
                END LOOP;
                RAISE DEBUG '[Job %] process_establishment: Ensured/Updated external_ident (type tax_ident) for successfully replaced ESTs.', p_job_id;

                EXECUTE format($$
                    UPDATE public.%I dt SET establishment_id = tbd.existing_est_id, last_completed_priority = %L, error = NULL, state = %L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id AND dt.row_id = ANY(%L);
                $$, v_data_table_name, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                RAISE DEBUG '[Job %] process_establishment: Updated _data table for % successfully replaced ESTs.', p_job_id, array_length(v_batch_upsert_success_row_ids, 1);
            END IF;
        END IF;
        DROP TABLE IF EXISTS temp_est_upsert_source;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Error during batch operation: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('process_establishment_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_establishment: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_job.data_table_name, v_step.priority, p_batch_row_ids);

    RAISE DEBUG '[Job %] process_establishment (Batch): Finished. New ESTs processed: %, Existing ESTs processed (attempted replace): %. Rows marked as error in this step: %',
        p_job_id, v_inserted_new_est_count, v_updated_existing_est_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_ests;
END;
$process_establishment$;

END;
