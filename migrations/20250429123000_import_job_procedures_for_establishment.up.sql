BEGIN;

-- Procedure to analyse base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_establishment$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name', 'data_source_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date', 'status_id_missing'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['data_source_code', 'sector_code', 'unit_size_code', 'birth_date', 'death_date'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get default status_id -- Removed
    -- SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    -- RAISE DEBUG '[Job %] analyse_establishment: Default status_id found: %', p_job_id, v_default_status_id;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id;
    END IF;

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id as data_row_id,
                ds.id as resolved_data_source_id,
                -- s.id as resolved_status_id, -- Removed status lookup
                sec.id as resolved_sector_id,
                us.id as resolved_unit_size_id,
                (import.safe_cast_to_date(dt_sub.birth_date)).p_value as resolved_typed_birth_date,
                (import.safe_cast_to_date(dt_sub.birth_date)).p_error_message as birth_date_error_msg,
                (import.safe_cast_to_date(dt_sub.death_date)).p_value as resolved_typed_death_date,
                (import.safe_cast_to_date(dt_sub.death_date)).p_error_message as death_date_error_msg
            FROM public.%1$I dt_sub
            LEFT JOIN public.data_source_available ds ON NULLIF(dt_sub.data_source_code, '') IS NOT NULL AND ds.code = NULLIF(dt_sub.data_source_code, '')
            -- LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = NULLIF(dt_sub.status_code, '') AND s.active = true -- Removed
            LEFT JOIN public.sector_available sec ON NULLIF(dt_sub.sector_code, '') IS NOT NULL AND sec.code = NULLIF(dt_sub.sector_code, '')
            LEFT JOIN public.unit_size_available us ON NULLIF(dt_sub.unit_size_code, '') IS NOT NULL AND us.code = NULLIF(dt_sub.unit_size_code, '')
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action != 'skip' -- Exclude skipped rows
        )
        UPDATE public.%2$I dt SET
            data_source_id = l.resolved_data_source_id,
            -- status_id = CASE ... END, -- Removed: status_id is now populated by 'status' step
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            typed_birth_date = l.resolved_typed_birth_date,
            typed_death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN dt.name IS NULL OR trim(dt.name) = '' THEN 'error'::public.import_data_state
                        WHEN dt.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE -- Added action update
                        WHEN dt.name IS NULL OR trim(dt.name) = '' THEN 'skip'::public.import_row_action_type
                        WHEN dt.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            error = CASE
                        WHEN dt.name IS NULL OR trim(dt.name) = '' THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('name', 'Missing required name')
                        WHEN dt.status_id IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('status_code', 'Status code could not be resolved and is required for this operation.')
                        ELSE 
                            CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END
                    END,
            invalid_codes = CASE
                                WHEN (dt.name IS NOT NULL AND trim(dt.name) != '') AND dt.status_id IS NOT NULL THEN -- Only populate invalid_codes if no fatal error in this step
                                    jsonb_strip_nulls(
                                     COALESCE(dt.invalid_codes, '{}'::jsonb) - %4$L::TEXT[] || 
                                     jsonb_build_object('data_source_code', CASE WHEN NULLIF(dt.data_source_code, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code', CASE WHEN NULLIF(dt.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN dt.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code', CASE WHEN NULLIF(dt.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN dt.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date', CASE WHEN NULLIF(dt.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN dt.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date', CASE WHEN NULLIF(dt.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN dt.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes -- Keep existing invalid_codes if it's a fatal status_id error
                            END,
            last_completed_priority = %5$L -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.row_id = ANY($1) AND dt.action != 'skip'; -- Ensure main update also excludes skipped
    $$,
        v_job.data_table_name /* %1$I */,                           -- For lookups CTE
        v_job.data_table_name /* %2$I */,                           -- For main UPDATE target
        v_error_keys_to_clear_arr /* %3$L */,                       -- For error CASE (clear)
        v_invalid_code_keys_arr /* %4$L */,                         -- For invalid_codes CASE (clear old)
        v_step.priority /* %5$L */                                  -- For last_completed_priority (always this step's priority)
    );

    RAISE DEBUG '[Job %] analyse_establishment: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (error ?| %2$L::text[])$$,
                       v_job.data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
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

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_job.data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, 'analyse_establishment');

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_establishment$;


-- Procedure to operate (insert/update/upsert) base establishment data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_establishment(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_establishment$
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
    v_inserted_new_est_count INT := 0;
    v_updated_existing_est_count INT := 0; -- Tracks rows intended for replace/update
    v_actually_replaced_or_updated_est_count INT := 0; -- Tracks rows successfully processed by batch function
    error_message TEXT;
    v_batch_upsert_result RECORD;
    v_batch_result RECORD; -- Declaration for the loop variable used in demotion
    v_batch_upsert_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_batch_upsert_success_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    -- Removed v_has_*_col flags, will use v_job_mode
    v_select_enterprise_id_expr TEXT := 'NULL::INTEGER';
    v_select_legal_unit_id_expr TEXT := 'NULL::INTEGER';
    v_select_primary_for_legal_unit_expr TEXT := 'NULL::BOOLEAN';
    v_select_primary_for_enterprise_expr TEXT := 'NULL::BOOLEAN';
    rec_created_est RECORD;
    rec_ident_type public.external_ident_type_active;
    v_ident_value TEXT;
    sample_data_row RECORD;
    v_select_list TEXT;
    v_job_mode public.import_mode; -- Added for job mode
    rec_demotion_es RECORD; -- For establishment demotion
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_establishment (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    v_job_mode := v_definition.mode;
    IF v_job_mode IS NULL OR v_job_mode NOT IN ('establishment_formal', 'establishment_informal') THEN
        RAISE EXCEPTION '[Job %] Invalid or missing mode for establishment processing: %. Expected ''establishment_formal'' or ''establishment_informal''.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_establishment: Job mode is %', p_job_id, v_job_mode;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id;
    END IF;

    v_strategy := v_definition.strategy;
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
        data_row_id INTEGER PRIMARY KEY,
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
        action public.import_row_action_type,
        founding_row_id INTEGER
    ) ON COMMIT DROP;

    v_select_list := format(
        'dt.row_id, dt.founding_row_id, dt.tax_ident, %s AS legal_unit_id, %s AS primary_for_legal_unit, %s AS enterprise_id, %s AS primary_for_enterprise, dt.name, dt.typed_birth_date, dt.typed_death_date, dt.derived_valid_after, dt.derived_valid_from, dt.derived_valid_to, dt.sector_id, dt.unit_size_id, dt.status_id, dt.data_source_id, dt.establishment_id, dt.invalid_codes, dt.edit_by_user_id, dt.edit_at, dt.edit_comment, dt.action',
        v_select_legal_unit_id_expr,
        v_select_primary_for_legal_unit_expr,
        v_select_enterprise_id_expr,
        v_select_primary_for_enterprise_expr
    );

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, tax_ident, legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, typed_birth_date, typed_death_date,
            valid_after, valid_from, valid_to, sector_id, unit_size_id, status_id, data_source_id,
            existing_est_id, invalid_codes, edit_by_user_id, edit_at, edit_comment, action
        )
        SELECT %1$s
         FROM public.%2$I dt WHERE dt.row_id = ANY($1) AND dt.action != 'skip';
    $$, v_select_list /* %1$s */, v_data_table_name /* %2$I */);
    RAISE DEBUG '[Job %] process_establishment: Fetching batch data (including invalid_codes and founding_row_id): %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Log sample data from temp_batch_data after initial population
    FOR sample_data_row IN SELECT * FROM temp_batch_data LIMIT 5 LOOP
        RAISE DEBUG '[Job %] process_establishment: Sample temp_batch_data after fetch: data_row_id=%, tax_ident=%, legal_unit_id=%, pflu=%, enterprise_id=%, pfe=%, name=%, action=%',
                     p_job_id, sample_data_row.data_row_id, sample_data_row.tax_ident, sample_data_row.legal_unit_id, sample_data_row.primary_for_legal_unit, sample_data_row.enterprise_id, sample_data_row.primary_for_enterprise, sample_data_row.name, sample_data_row.action;
    END LOOP;

    -- Resolve primary_for_legal_unit conflicts within the current batch
    IF v_job_mode = 'establishment_formal' THEN
        RAISE DEBUG '[Job %] process_establishment: Resolving primary_for_legal_unit conflicts within temp_batch_data.', p_job_id;
        WITH BatchPrimariesES_PFLU AS (
            SELECT
                data_row_id,
                FIRST_VALUE(data_row_id) OVER (
                    PARTITION BY legal_unit_id, daterange(valid_after, valid_to, '(]')
                    ORDER BY existing_est_id ASC NULLS LAST, data_row_id ASC
                ) as winner_data_row_id
            FROM temp_batch_data
            WHERE action IN ('replace', 'update')
              AND primary_for_legal_unit = true
              AND legal_unit_id IS NOT NULL
        )
        UPDATE temp_batch_data tbd
        SET primary_for_legal_unit = false
        FROM BatchPrimariesES_PFLU bp
        WHERE tbd.data_row_id = bp.data_row_id
          AND tbd.data_row_id != bp.winner_data_row_id
          AND tbd.primary_for_legal_unit = true;
        IF FOUND THEN RAISE DEBUG '[Job %] process_establishment: Resolved PFLU conflicts in temp_batch_data.', p_job_id; END IF;
    END IF;

    -- Resolve primary_for_enterprise conflicts within the current batch (for informal establishments)
    IF v_job_mode = 'establishment_informal' THEN
        RAISE DEBUG '[Job %] process_establishment: Resolving primary_for_enterprise conflicts for informal ESTs within temp_batch_data.', p_job_id;
        WITH BatchPrimariesES_PFE AS (
            SELECT
                data_row_id,
                FIRST_VALUE(data_row_id) OVER (
                    PARTITION BY enterprise_id, daterange(valid_after, valid_to, '(]')
                    ORDER BY existing_est_id ASC NULLS LAST, data_row_id ASC
                ) as winner_data_row_id
            FROM temp_batch_data
            WHERE action IN ('replace', 'update')
              AND primary_for_enterprise = true
              AND enterprise_id IS NOT NULL
        )
        UPDATE temp_batch_data tbd
        SET primary_for_enterprise = false
        FROM BatchPrimariesES_PFE bp
        WHERE tbd.data_row_id = bp.data_row_id
          AND tbd.data_row_id != bp.winner_data_row_id
          AND tbd.primary_for_enterprise = true;
        IF FOUND THEN RAISE DEBUG '[Job %] process_establishment: Resolved PFE conflicts for informal ESTs in temp_batch_data.', p_job_id; END IF;
    END IF;

    CREATE TEMP TABLE temp_created_ests (
        data_row_id INTEGER PRIMARY KEY,
        new_establishment_id INT NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE temp_processed_action_ids (
        data_row_id INTEGER PRIMARY KEY,
        actual_establishment_id INT NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE temp_es_demotion_ops (
        row_id INTEGER PRIMARY KEY, founding_row_id INTEGER, id INT NOT NULL, valid_after DATE NOT NULL, valid_to DATE NOT NULL,
        name TEXT, birth_date DATE, death_date DATE, active BOOLEAN, sector_id INT, unit_size_id INT, status_id INT,
        legal_unit_id INT, primary_for_legal_unit BOOLEAN, enterprise_id INT, primary_for_enterprise BOOLEAN,
        data_source_id INT, invalid_codes JSONB, edit_by_user_id INT, edit_at TIMESTAMPTZ, edit_comment TEXT
    ) ON COMMIT DROP;

    BEGIN
        -- Demotion logic for primary_for_legal_unit (formal establishments)
        IF v_job_mode = 'establishment_formal' THEN
            RAISE DEBUG '[Job %] process_establishment: Starting demotion of conflicting PFLU ESTs.', p_job_id;
            INSERT INTO temp_es_demotion_ops (
                id, valid_after, valid_to, name, birth_date, death_date, active, sector_id, unit_size_id, status_id,
                legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise,
                data_source_id, invalid_codes, edit_by_user_id, edit_at, edit_comment, row_id
            )
            SELECT
                ex_es.id, ipes.new_primary_valid_after, ipes.new_primary_valid_to,
                ex_es.name, ex_es.birth_date, ex_es.death_date, ex_es.active, ex_es.sector_id, ex_es.unit_size_id, ex_es.status_id,
                ex_es.legal_unit_id, false, ex_es.enterprise_id, ex_es.primary_for_enterprise,
                ex_es.data_source_id, ex_es.invalid_codes, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                COALESCE(ex_es.edit_comment || '; ', '') || 'Demoted (PFLU): EST ' || COALESCE(ipes.incoming_est_id::TEXT, 'NEW') ||
                ' became primary for LU ' || ipes.target_legal_unit_id || ' for period ' || ipes.new_primary_valid_after || ' to ' || ipes.new_primary_valid_to || ' by job ' || p_job_id,
                row_number() OVER (ORDER BY ex_es.id, ipes.new_primary_valid_after)
            FROM public.establishment ex_es
            JOIN (
                SELECT s.existing_est_id AS incoming_est_id, s.legal_unit_id AS target_legal_unit_id, s.valid_after AS new_primary_valid_after, s.valid_to AS new_primary_valid_to, s.edit_by_user_id AS demotion_edit_by_user_id, s.edit_at AS demotion_edit_at
                FROM temp_batch_data s WHERE s.action IN ('replace', 'update') AND s.primary_for_legal_unit = true AND s.legal_unit_id IS NOT NULL
            ) AS ipes ON ex_es.legal_unit_id = ipes.target_legal_unit_id
            WHERE ex_es.id != ipes.incoming_est_id AND ex_es.primary_for_legal_unit = true
              AND public.after_to_overlaps(ex_es.valid_after, ex_es.valid_to, ipes.new_primary_valid_after, ipes.new_primary_valid_to);

            IF FOUND THEN
                RAISE DEBUG '[Job %] process_establishment: Identified % ESTs for PFLU demotion.', p_job_id, (SELECT count(*) FROM temp_es_demotion_ops);
                FOR v_batch_result IN
                    SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                        p_target_schema_name => 'public',
                        p_target_table_name => 'establishment',
                        p_source_schema_name => 'pg_temp',
                        p_source_table_name => 'temp_es_demotion_ops',
                        p_unique_columns => '[]'::jsonb,
                        p_ephemeral_columns => ARRAY['edit_comment','edit_by_user_id','edit_at'],
                        p_id_column_name => 'id'
                    )
                LOOP
                    IF v_batch_result.status = 'ERROR' THEN RAISE WARNING '[Job %] process_establishment: Error PFLU demotion EST ID %: %', p_job_id,v_batch_result.upserted_record_id,v_batch_result.error_message;
                    ELSE RAISE DEBUG '[Job %] process_establishment: Success PFLU demotion EST ID %',p_job_id,v_batch_result.upserted_record_id; END IF;
                END LOOP;
                DELETE FROM temp_es_demotion_ops;
            ELSE RAISE DEBUG '[Job %] process_establishment: No existing PFLU ESTs to demote.', p_job_id; END IF;
        END IF;

        -- Demotion logic for primary_for_enterprise (informal establishments)
        IF v_job_mode = 'establishment_informal' THEN
            RAISE DEBUG '[Job %] process_establishment: Starting demotion of conflicting PFE informal ESTs.', p_job_id;
            INSERT INTO temp_es_demotion_ops (
                id, valid_after, valid_to, name, birth_date, death_date, active, sector_id, unit_size_id, status_id,
                legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise,
                data_source_id, invalid_codes, edit_by_user_id, edit_at, edit_comment, row_id
            )
            SELECT
                ex_es.id, ipes.new_primary_valid_after, ipes.new_primary_valid_to,
                ex_es.name, ex_es.birth_date, ex_es.death_date, ex_es.active, ex_es.sector_id, ex_es.unit_size_id, ex_es.status_id,
                ex_es.legal_unit_id, ex_es.primary_for_legal_unit, ex_es.enterprise_id, false, -- Demoting primary_for_enterprise
                ex_es.data_source_id, ex_es.invalid_codes, ipes.demotion_edit_by_user_id, ipes.demotion_edit_at,
                COALESCE(ex_es.edit_comment || '; ', '') || 'Demoted (PFE): EST ' || COALESCE(ipes.incoming_est_id::TEXT, 'NEW') ||
                ' became primary for EN ' || ipes.target_enterprise_id || ' for period ' || ipes.new_primary_valid_after || ' to ' || ipes.new_primary_valid_to || ' by job ' || p_job_id,
                row_number() OVER (ORDER BY ex_es.id, ipes.new_primary_valid_after)
            FROM public.establishment ex_es
            JOIN (
                SELECT s.existing_est_id AS incoming_est_id, s.enterprise_id AS target_enterprise_id, s.valid_after AS new_primary_valid_after, s.valid_to AS new_primary_valid_to, s.edit_by_user_id AS demotion_edit_by_user_id, s.edit_at AS demotion_edit_at
                FROM temp_batch_data s WHERE s.action IN ('replace', 'update') AND s.primary_for_enterprise = true AND s.enterprise_id IS NOT NULL
            ) AS ipes ON ex_es.enterprise_id = ipes.target_enterprise_id
            WHERE ex_es.id != ipes.incoming_est_id AND ex_es.primary_for_enterprise = true
              AND public.after_to_overlaps(ex_es.valid_after, ex_es.valid_to, ipes.new_primary_valid_after, ipes.new_primary_valid_to);

            IF FOUND THEN
                RAISE DEBUG '[Job %] process_establishment: Identified % informal ESTs for PFE demotion.', p_job_id, (SELECT count(*) FROM temp_es_demotion_ops);
                FOR v_batch_result IN
                    SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                        p_target_schema_name => 'public',
                        p_target_table_name => 'establishment',
                        p_source_schema_name => 'pg_temp',
                        p_source_table_name => 'temp_es_demotion_ops',
                        p_unique_columns => '[]'::jsonb,
                        p_ephemeral_columns => ARRAY['edit_comment','edit_by_user_id','edit_at'],
                        p_id_column_name => 'id'
                    )
                LOOP
                    IF v_batch_result.status = 'ERROR' THEN RAISE WARNING '[Job %] process_establishment: Error PFE demotion EST ID %: %',p_job_id,v_batch_result.upserted_record_id,v_batch_result.error_message;
                    ELSE RAISE DEBUG '[Job %] process_establishment: Success PFE demotion EST ID %',p_job_id,v_batch_result.upserted_record_id; END IF;
                END LOOP;
                DELETE FROM temp_es_demotion_ops;
            ELSE RAISE DEBUG '[Job %] process_establishment: No existing PFE informal ESTs to demote.', p_job_id; END IF;
        END IF;

        RAISE DEBUG '[Job %] process_establishment: Handling INSERTS for new ESTs using MERGE.', p_job_id;

        -- Log data going into MERGE for inserts
        FOR sample_data_row IN SELECT * FROM temp_batch_data WHERE action = 'insert' LIMIT 5 LOOP
            RAISE DEBUG '[Job %] process_establishment: MERGE INSERT source: data_row_id=%, legal_unit_id=%, pflu=%, enterprise_id=%, pfe=%, name=%',
                         p_job_id, sample_data_row.data_row_id, sample_data_row.legal_unit_id, sample_data_row.primary_for_legal_unit, sample_data_row.enterprise_id, sample_data_row.primary_for_enterprise, sample_data_row.name;
        END LOOP;

        WITH source_for_insert AS (
            SELECT
                data_row_id, name, typed_birth_date, typed_death_date,
                sector_id, unit_size_id, status_id, data_source_id,
                legal_unit_id, primary_for_legal_unit,
                enterprise_id, primary_for_enterprise,
                valid_after, valid_to, invalid_codes, -- Changed valid_from to valid_after
                edit_by_user_id, edit_at, edit_comment
            FROM temp_batch_data WHERE action = 'insert'
        ),
        merged_establishments AS (
            MERGE INTO public.establishment est
            USING source_for_insert sfi
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (
                    legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, birth_date, death_date,
                    sector_id, unit_size_id, status_id, data_source_id, invalid_codes, -- Added invalid_codes
                    valid_after, valid_to, -- Changed valid_from to valid_after
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    sfi.legal_unit_id, -- Will be NULL if mode is informal, based on prior select into temp_batch_data
                    sfi.primary_for_legal_unit, -- Will be NULL if mode is informal
                    sfi.enterprise_id, -- Will be NULL if mode is formal
                    sfi.primary_for_enterprise, -- Will be NULL if mode is formal
                    sfi.name, sfi.typed_birth_date, sfi.typed_death_date,
                    sfi.sector_id, sfi.unit_size_id, sfi.status_id, sfi.data_source_id, sfi.invalid_codes, -- Added sfi.invalid_codes
                    sfi.valid_after, sfi.valid_to, -- Changed sfi.valid_from to sfi.valid_after
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
                CALL import.shared_upsert_external_idents_for_unit(
                    p_job_id => p_job_id,
                    p_data_table_name => v_data_table_name,
                    p_data_row_id => rec_created_est.data_row_id,
                    p_unit_id => rec_created_est.new_establishment_id,
                    p_unit_type => 'establishment',
                    p_edit_by_user_id => rec_created_est.edit_by_user_id,
                    p_edit_at => rec_created_est.edit_at,
                    p_edit_comment => rec_created_est.edit_comment
                );
            END LOOP;
            RAISE DEBUG '[Job %] process_establishment: Processed external idents for % new ESTs using shared procedure.', p_job_id, v_inserted_new_est_count;

            -- Update temp_batch_data with the new_establishment_id for subsequent 'replace' rows of the same logical entity
            -- This uses tax_ident as the proxy for entity_signature. A more robust solution might involve
            -- passing entity_signature or rn_in_batch_for_entity from the analyse step.
            FOR rec_created_est IN SELECT tce.data_row_id, tce.new_establishment_id, tbd.tax_ident
                                   FROM temp_created_ests tce
                                   JOIN temp_batch_data tbd ON tce.data_row_id = tbd.data_row_id
            LOOP
                UPDATE temp_batch_data tbd_update
                SET existing_est_id = rec_created_est.new_establishment_id
                WHERE tbd_update.tax_ident = rec_created_est.tax_ident -- Match by tax_ident
                  AND tbd_update.action = 'replace'                   -- Only for 'replace' actions
                  AND tbd_update.data_row_id != rec_created_est.data_row_id; -- Not the original insert row
                RAISE DEBUG '[Job %] process_establishment: Updated temp_batch_data.existing_est_id to % for tax_ident % on replace rows.', p_job_id, rec_created_est.new_establishment_id, rec_created_est.tax_ident;
            END LOOP;

            EXECUTE format($$
                UPDATE public.%1$I dt SET
                    establishment_id = tce.new_establishment_id, -- This updates the _data table for the 'insert' rows
                    error = NULL,
                    state = %2$L
                FROM temp_created_ests tce
                WHERE dt.row_id = tce.data_row_id AND dt.state != 'error';
            $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */);
            RAISE DEBUG '[Job %] process_establishment: Updated _data table for % new ESTs.', p_job_id, v_inserted_new_est_count;
        END IF;

        RAISE DEBUG '[Job %] process_establishment: Handling REPLACES for existing ESTs via batch_upsert.', p_job_id;

        CREATE TEMP TABLE temp_est_upsert_source (
            row_id INTEGER PRIMARY KEY,
            founding_row_id INTEGER,
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
            row_id, founding_row_id, id, valid_after, valid_to, legal_unit_id, primary_for_legal_unit, enterprise_id, primary_for_enterprise, name, birth_date, death_date, active,
            sector_id, unit_size_id, status_id, data_source_id, invalid_codes, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, tbd.founding_row_id, tbd.existing_est_id, tbd.valid_after, tbd.valid_to, -- Use tbd.valid_after directly
            tbd.legal_unit_id, -- Value from temp_batch_data, correctly nulled by mode if needed
            tbd.primary_for_legal_unit, -- Value from temp_batch_data
            tbd.enterprise_id, -- Value from temp_batch_data
            tbd.primary_for_enterprise, -- Value from temp_batch_data
            tbd.name, tbd.typed_birth_date, tbd.typed_death_date, true, -- Assuming active=true
            tbd.sector_id, tbd.unit_size_id, tbd.status_id, tbd.data_source_id,
            tbd.invalid_codes,
            tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment
        FROM (
            SELECT DISTINCT ON (existing_est_id, valid_after) *
            FROM temp_batch_data
            WHERE action = 'replace'
            ORDER BY existing_est_id ASC NULLS LAST, valid_after ASC, data_row_id ASC
        ) tbd;

        GET DIAGNOSTICS v_updated_existing_est_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_establishment: Populated temp_est_upsert_source with % rows for batch replace.', p_job_id, v_updated_existing_est_count;

        IF v_updated_existing_est_count > 0 THEN
            RAISE DEBUG '[Job %] process_establishment: Calling batch_insert_or_replace_generic_valid_time_table for establishment.', p_job_id;
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'establishment',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_est_upsert_source',
                    p_unique_columns => '[]'::jsonb,
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%1$I SET state = %2$L, error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_establishment_error', %3$L)
                        -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %4$L;
                    $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, v_batch_upsert_result.error_message /* %3$L */, v_batch_upsert_result.source_row_id /* %4$L */);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                    INSERT INTO temp_processed_action_ids (data_row_id, actual_establishment_id)
                    VALUES (v_batch_upsert_result.source_row_id, v_batch_upsert_result.upserted_record_id); -- Corrected to upserted_record_id
                END IF;
            END LOOP;

            v_actually_replaced_or_updated_est_count := array_length(v_batch_upsert_success_row_ids, 1);
            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_establishment: Batch replace finished. Success: %, Errors: %', p_job_id, v_actually_replaced_or_updated_est_count, v_error_count;

            IF v_actually_replaced_or_updated_est_count > 0 THEN
                FOR rec_created_est IN
                    SELECT
                        tbd.data_row_id,
                        tpai.actual_establishment_id as new_establishment_id,
                        tbd.edit_by_user_id,
                        tbd.edit_at,
                        tbd.edit_comment
                    FROM temp_batch_data tbd
                    JOIN temp_processed_action_ids tpai ON tbd.data_row_id = tpai.data_row_id
                    WHERE tbd.data_row_id = ANY(v_batch_upsert_success_row_ids) -- Redundant due to JOIN, but safe
                LOOP
                     CALL import.shared_upsert_external_idents_for_unit(
                        p_job_id => p_job_id,
                        p_data_table_name => v_data_table_name,
                        p_data_row_id => rec_created_est.data_row_id,
                        p_unit_id => rec_created_est.new_establishment_id,
                        p_unit_type => 'establishment',
                        p_edit_by_user_id => rec_created_est.edit_by_user_id,
                        p_edit_at => rec_created_est.edit_at,
                        p_edit_comment => rec_created_est.edit_comment
                    );
                END LOOP;
                RAISE DEBUG '[Job %] process_establishment: Ensured/Updated external_ident for % successfully replaced ESTs using shared procedure.', p_job_id, v_actually_replaced_or_updated_est_count;

                EXECUTE format($$
                    UPDATE public.%1$I dt SET
                        establishment_id = tpai.actual_establishment_id,
                        error = NULL,
                        state = %2$L
                    FROM temp_processed_action_ids tpai
                    WHERE dt.row_id = tpai.data_row_id AND dt.row_id = ANY($1); -- dt.row_id = ANY ensures we only update rows from this batch
                $$, v_data_table_name /* %1$I */, 'processing'::public.import_data_state /* %2$L */) USING v_batch_upsert_success_row_ids;
                RAISE DEBUG '[Job %] process_establishment: Updated _data table for % successfully replaced ESTs with correct establishment_id.', p_job_id, v_actually_replaced_or_updated_est_count;
            END IF;
        END IF; -- End v_updated_existing_est_count > 0 (renamed from v_updated_existing_est_count for clarity of original intent)
        DROP TABLE IF EXISTS temp_est_upsert_source;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_establishment: Error during batch operation: %', p_job_id, replace(error_message, '%', '%%');
        UPDATE public.import_job
        SET error = jsonb_build_object('process_establishment_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_establishment: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    -- The framework now handles advancing priority for all rows, including 'skip'. No update needed here.

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_establishment (Batch): Finished in % ms. New ESTs (action=insert): %, ESTs for replace/update: % (succeeded: %, errored: %). Total Errors in step: %',
        p_job_id, round(v_duration_ms, 2), v_inserted_new_est_count, v_updated_existing_est_count, v_actually_replaced_or_updated_est_count, v_error_count, v_error_count; -- Assuming v_error_count is total for replace/update part

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_ests;
    DROP TABLE IF EXISTS temp_processed_action_ids;
    DROP TABLE IF EXISTS temp_es_demotion_ops;
END;
$process_establishment$;

END;
