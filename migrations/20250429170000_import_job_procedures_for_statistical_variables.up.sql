-- Migration: import_job_procedures_for_stats
-- Implements the analyse and operation procedures for the statistical_variables import target.

BEGIN;

-- Helper function for safe integer casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_integer(
    IN p_text_value TEXT,
    OUT p_value INTEGER,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_value::INTEGER;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid integer format: ''' || p_text_value || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_value || ''' to integer. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;

-- Helper function for safe boolean casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_boolean(
    IN p_text_value TEXT,
    OUT p_value BOOLEAN,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_value::BOOLEAN;
    EXCEPTION
        WHEN invalid_text_representation THEN -- Common for boolean cast errors
            p_error_message := 'Invalid boolean format: ''' || p_text_value || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_value || ''' to boolean. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;

-- Procedure to analyse statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_statistical_variables$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_conditions_sql TEXT := '';
    v_error_json_sql TEXT := '';
    v_error_keys_to_clear_list TEXT[];
    v_add_separator BOOLEAN := FALSE;
BEGIN
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; 

    IF v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found in snapshot', p_job_id;
    END IF;

    -- No longer filter v_stat_data_cols by step_id here.
    -- The loop will iterate over all source_input columns and join to stat_definition_active.
    IF v_stat_data_cols IS NULL OR jsonb_array_length(v_stat_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_statistical_variables: No data columns found in snapshot. Skipping analysis.', p_job_id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    v_add_separator := FALSE;
    FOR v_col_rec IN
        SELECT
            idc.value->>'column_name' as col_name, -- idc for import_data_column
            sda.type
        FROM jsonb_array_elements(v_stat_data_cols) idc -- Iterate over all data columns from snapshot
        JOIN public.stat_definition_active sda ON sda.code = (idc.value->>'column_name') -- Join to find actual stats
        WHERE idc.value->>'purpose' = 'source_input' -- Consider only source_input columns
    LOOP
        IF v_add_separator THEN
            v_error_conditions_sql := v_error_conditions_sql || ' OR ';
            v_error_json_sql := v_error_json_sql || ' || ';
        END IF;
        
        v_error_conditions_sql := v_error_conditions_sql || format(
            '(dt.%I IS NOT NULL AND (import.safe_cast_to_%s(dt.%I)).p_error_message IS NOT NULL)', -- Check p_error_message
            v_col_rec.col_name,
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END,
            v_col_rec.col_name
        );
        
        v_error_json_sql := v_error_json_sql || format(
            'jsonb_build_object(%L, CASE WHEN dt.%I IS NOT NULL THEN (import.safe_cast_to_%s(dt.%I)).p_error_message ELSE NULL END)', -- Use p_error_message
            v_col_rec.col_name,
            v_col_rec.col_name,
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END,
            v_col_rec.col_name
        );
        -- Removed assignment to v_invalid_codes_json_sql as it's not declared and errors are fatal for this step.
        v_error_keys_to_clear_list := array_append(v_error_keys_to_clear_list, v_col_rec.col_name);
        v_add_separator := TRUE;
    END LOOP;

    IF v_error_conditions_sql = '' THEN -- Should not happen if v_stat_data_cols is not empty
        v_error_conditions_sql := 'FALSE';
        v_error_json_sql := '''{}''::jsonb';
    END IF;

    v_sql := format($$
        UPDATE public.%I dt SET
            -- Determine state first
            state = CASE
                        WHEN %s THEN 'error'::public.import_data_state -- Error condition for this step
                        ELSE 'analysing'::public.import_data_state -- No error from this step
                    END,
            -- Then determine action based on the new state or existing action
            action = CASE
                        WHEN %s THEN 'skip'::public.import_row_action_type -- If this step causes an error, action becomes 'skip'
                        ELSE dt.action -- Otherwise, preserve existing action
                     END,
            error = CASE
                        WHEN %s THEN COALESCE(dt.error, '{}'::jsonb) || jsonb_strip_nulls(%s) -- Error condition for this step
                        ELSE CASE WHEN (dt.error - %L) = '{}'::jsonb THEN NULL ELSE (dt.error - %L) END -- Clear errors specific to this step if no new error
                    END,
            last_completed_priority = %s -- Always v_step.priority
        WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$,
        v_data_table_name,
        v_error_conditions_sql, -- For action CASE
        v_error_conditions_sql, -- For state CASE
        v_error_conditions_sql, v_error_json_sql, -- For error CASE (add)
        v_error_keys_to_clear_list, v_error_keys_to_clear_list, -- For error CASE (clear)
        v_step.priority, -- For last_completed_priority (always this step's priority)
        p_batch_row_ids
    );

    RAISE DEBUG '[Job %] analyse_statistical_variables: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
        ', v_data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_list)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_statistical_variables: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_statistical_variables_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_statistical_variables$;



-- Procedure to operate (insert/update/upsert) statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_statistical_variables$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition public.import_definition;
    v_step public.import_step;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_stat_count INT := 0;
    v_updated_existing_stat_count INT := 0;
    error_message TEXT;
    v_unpivot_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_batch_upsert_success_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_pk_col_name TEXT;
    v_stat_def RECORD;
    v_update_pk_sql TEXT := '';
    v_update_pk_sep TEXT := '';
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_employees_stat_def_exists BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Debug: Check if 'employees' stat definition exists
    SELECT EXISTS (SELECT 1 FROM public.stat_definition WHERE code = 'employees') INTO v_employees_stat_def_exists;
    RAISE DEBUG '[Job %] process_statistical_variables: Stat definition for "employees" exists: %', p_job_id, v_employees_stat_def_exists;
    IF NOT v_employees_stat_def_exists THEN
        RAISE WARNING '[Job %] process_statistical_variables: CRITICAL - Stat definition for "employees" NOT FOUND. This will cause 0 rows in temp_batch_data if employees is the only stat.', p_job_id;
    END IF;

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; 

    IF v_definition IS NULL OR
       v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition or import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found in snapshot', p_job_id;
    END IF;

    v_strategy := v_definition.strategy;
    v_edit_by_user_id := v_job.user_id;

    v_add_separator := FALSE;
    -- Iterate over all source_input columns from the snapshot and check if they are defined stats
    FOR v_col_rec IN 
        SELECT idc.value->>'column_name' as col_name
        FROM jsonb_array_elements(v_stat_data_cols) idc -- Full list from snapshot
        JOIN public.stat_definition_active sda ON sda.code = (idc.value->>'column_name') -- Check if it's a stat
        WHERE idc.value->>'purpose' = 'source_input' -- Only consider source_input columns
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        -- Ensure we only try to unpivot if the column actually has a non-empty, non-whitespace value.
        -- The IS NOT NULL check is good, but char_length(trim(...)) > 0 is more robust for TEXT fields that might contain only whitespace.
        v_unpivot_sql := v_unpivot_sql || format($$SELECT %L AS stat_code, dt.%I AS stat_value, dt.row_id AS data_row_id_from_source FROM public.%I dt WHERE dt.%I IS NOT NULL AND char_length(trim(dt.%I)) > 0 AND dt.row_id = ANY(%L) AND dt.action != 'skip'$$, 
                                                 v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, v_col_rec.col_name, p_batch_row_ids);
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
         RAISE DEBUG '[Job %] process_statistical_variables: No stat data columns found in snapshot for target % or all rows skipped. Skipping operation.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

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
    ELSIF v_job_mode IS NULL THEN -- Handling for stats_update jobs where mode is NULL
        RAISE DEBUG '[Job %] process_statistical_variables: Job mode is NULL, assuming stats update. Will select both LU and EST IDs from _data table, relying on external_idents step to have populated one.', p_job_id;
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_statistical_variables: Unhandled job mode % for unit ID selection. Expected one of (legal_unit, establishment_formal, establishment_informal) or NULL for stats updates.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_statistical_variables: Based on mode %, using lu_id_expr: %, est_id_expr: % for table %', 
        p_job_id, v_job_mode, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name;

    -- Debug: Count rows that should contribute to unpivoted_stats
    DECLARE
        v_potential_employee_rows INTEGER;
        v_potential_turnover_rows INTEGER;
    BEGIN
        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE employees IS NOT NULL AND char_length(trim(employees)) > 0 AND row_id = ANY(%L) AND action IS DISTINCT FROM ''skip''', v_data_table_name, p_batch_row_ids)
        INTO v_potential_employee_rows;
        RAISE DEBUG '[Job %] process_statistical_variables: Potential employee rows in batch (employees IS NOT NULL AND non-empty AND action != ''skip''): %', p_job_id, v_potential_employee_rows;

        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'turnover') THEN
            EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE turnover IS NOT NULL AND char_length(trim(turnover)) > 0 AND row_id = ANY(%L) AND action != ''skip''', v_data_table_name, p_batch_row_ids)
            INTO v_potential_turnover_rows;
            RAISE DEBUG '[Job %] process_statistical_variables: Potential turnover rows in batch (turnover IS NOT NULL AND non-empty AND action IS DISTINCT FROM ''skip''): %', p_job_id, v_potential_turnover_rows;
        ELSE
            RAISE DEBUG '[Job %] process_statistical_variables: Turnover column not present in %I.', p_job_id, v_data_table_name;
        END IF;
    END;

    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER, 
        legal_unit_id INT,
        establishment_id INT,
        valid_after DATE, -- Added
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        stat_definition_id INT,
        stat_value TEXT,
        existing_link_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        action public.import_row_action_type, 
        PRIMARY KEY (data_row_id, stat_definition_id) 
    ) ON COMMIT DROP;

    v_sql := format($$
        WITH unpivoted_stats AS ( %s )
        INSERT INTO temp_batch_data (
            data_row_id, legal_unit_id, establishment_id, valid_after, valid_from, valid_to, data_source_id,
            stat_definition_id, stat_value, edit_by_user_id, edit_at, edit_comment, action -- Added edit_comment
        )
        SELECT
            up.data_row_id_from_source, 
            %s, 
            %s, 
            dt.derived_valid_after, -- Added
            dt.derived_valid_from, 
            dt.derived_valid_to,   
            dt.data_source_id,
            sd.id, up.stat_value,
            dt.edit_by_user_id, dt.edit_at, dt.edit_comment, -- Added
            dt.action 
        FROM unpivoted_stats up
        JOIN public.%I dt ON up.data_row_id_from_source = dt.row_id 
        JOIN public.stat_definition sd ON sd.code = up.stat_code; 
    $$, v_unpivot_sql, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Fetching and unpivoting batch data (v_sql): %', p_job_id, v_sql;

    -- Debug: Count rows from the full SELECT statement that would feed temp_batch_data
    DECLARE
        full_select_count INTEGER;
        debug_full_select_sql TEXT;
    BEGIN
        debug_full_select_sql := format($$
            WITH unpivoted_stats AS ( %s )
            SELECT COUNT(*)
            FROM unpivoted_stats up
            JOIN public.%I dt ON up.data_row_id_from_source = dt.row_id 
            JOIN public.stat_definition sd ON sd.code = up.stat_code;
        $$, v_unpivot_sql, v_data_table_name);
        RAISE DEBUG '[Job %] process_statistical_variables: v_unpivot_sql: %', p_job_id, v_unpivot_sql;
        EXECUTE debug_full_select_sql INTO full_select_count;
        RAISE DEBUG '[Job %] process_statistical_variables: Expected row count for temp_batch_data (from SELECT part of INSERT): %', p_job_id, full_select_count;
    END;
    
    EXECUTE v_sql; -- This is the original INSERT INTO temp_batch_data

    -- Debugging block to inspect temp_batch_data
    DECLARE
        action_counts JSONB;
        sample_stat_row RECORD;
        tbd_row_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO tbd_row_count FROM temp_batch_data;
        RAISE DEBUG '[Job %] process_statistical_variables: temp_batch_data populated with % rows.', p_job_id, tbd_row_count;

        SELECT jsonb_object_agg(action, count)
        INTO action_counts
        FROM (
            SELECT action, COUNT(*) as count
            FROM temp_batch_data
            GROUP BY action
        ) AS counts;
        RAISE DEBUG '[Job %] process_statistical_variables: Action counts in temp_batch_data: %', p_job_id, action_counts;

        FOR sample_stat_row IN SELECT * FROM temp_batch_data LIMIT 5 LOOP
            RAISE DEBUG '[Job %] process_statistical_variables: Sample temp_batch_data row: data_row_id=%, legal_unit_id=%, establishment_id=%, stat_definition_id=%, stat_value=%, action=%, edit_comment=%',
                         p_job_id, sample_stat_row.data_row_id, sample_stat_row.legal_unit_id, sample_stat_row.establishment_id, sample_stat_row.stat_definition_id, sample_stat_row.stat_value, sample_stat_row.action, sample_stat_row.edit_comment;
        END LOOP;
    END;
    -- End Debugging block

    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_link_id = sfu.id
        FROM public.stat_for_unit sfu
        WHERE sfu.stat_definition_id = tbd.stat_definition_id
          AND CASE
                WHEN %L = 'legal_unit' THEN -- job_mode is legal_unit
                    sfu.legal_unit_id = tbd.legal_unit_id AND sfu.establishment_id IS NULL
                WHEN %L IN ('establishment_formal', 'establishment_informal') THEN -- job_mode is establishment_*
                    sfu.establishment_id = tbd.establishment_id AND sfu.legal_unit_id IS NULL
                WHEN %L IS NULL THEN -- job_mode is NULL (e.g. stats_update)
                    (sfu.legal_unit_id = tbd.legal_unit_id AND tbd.legal_unit_id IS NOT NULL AND sfu.establishment_id IS NULL AND tbd.establishment_id IS NULL) OR
                    (sfu.establishment_id = tbd.establishment_id AND tbd.establishment_id IS NOT NULL AND sfu.legal_unit_id IS NULL AND tbd.legal_unit_id IS NULL)
                ELSE FALSE -- Should not happen
              END;
    $$, v_job_mode, v_job_mode, v_job_mode);
    RAISE DEBUG '[Job %] process_statistical_variables: Determining existing link IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    CREATE TEMP TABLE temp_created_stats (
        data_row_id INTEGER,
        stat_definition_id INT,
        new_stat_for_unit_id INT NOT NULL,
        PRIMARY KEY (data_row_id, stat_definition_id)
    ) ON COMMIT DROP;

    -- Create temp source table for batch upsert (for replaces) *before* the inner BEGIN block
    CREATE TEMP TABLE temp_stat_upsert_source (
        row_id INTEGER, 
        id INT, 
        valid_after DATE NOT NULL, -- Changed
        valid_to DATE NOT NULL,
        stat_definition_id INT,
        legal_unit_id INT,
        establishment_id INT,
        value_string TEXT, -- Changed from generic 'value'
        value_int INTEGER,
        value_float DOUBLE PRECISION,
        value_bool BOOLEAN,
        data_source_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT,
        PRIMARY KEY (row_id, stat_definition_id) 
    ) ON COMMIT DROP;

    BEGIN
        RAISE DEBUG '[Job %] process_statistical_variables: Handling INSERTS for new stats using MERGE.', p_job_id;

        WITH source_for_insert AS (
            SELECT 
                sfi.*, 
                sd.type as stat_type -- Get the type of the statistic
            FROM temp_batch_data sfi
            JOIN public.stat_definition sd ON sfi.stat_definition_id = sd.id
            WHERE sfi.action = 'insert'
        ),
        merged_stats AS (
            MERGE INTO public.stat_for_unit sfu
            USING source_for_insert sfi
            ON 1 = 0 
            WHEN NOT MATCHED THEN
                INSERT (
                    stat_definition_id, legal_unit_id, establishment_id, 
                    value_string, value_int, value_float, value_bool,
                    data_source_id, valid_after, valid_to, -- Changed
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    sfi.stat_definition_id,
                    CASE 
                        WHEN v_job_mode = 'legal_unit' THEN sfi.legal_unit_id
                        WHEN v_job_mode IS NULL THEN sfi.legal_unit_id -- For stats_update, external_idents determined this
                        ELSE NULL 
                    END,
                    CASE 
                        WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN sfi.establishment_id
                        WHEN v_job_mode IS NULL THEN sfi.establishment_id -- For stats_update, external_idents determined this
                        ELSE NULL 
                    END,
                    CASE sfi.stat_type WHEN 'string' THEN sfi.stat_value ELSE NULL END,
                    CASE sfi.stat_type WHEN 'int'    THEN (import.safe_cast_to_integer(sfi.stat_value)).p_value ELSE NULL END,
                    CASE sfi.stat_type WHEN 'float'  THEN (import.safe_cast_to_numeric(sfi.stat_value)).p_value ELSE NULL END,
                    CASE sfi.stat_type WHEN 'bool'   THEN (import.safe_cast_to_boolean(sfi.stat_value)).p_value ELSE NULL END,
                    sfi.data_source_id, sfi.valid_after, sfi.valid_to, -- Changed
                    sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment -- Use sfi.edit_comment
                )
            RETURNING sfu.id AS new_stat_for_unit_id, sfi.data_row_id, sfi.stat_definition_id
        )
        INSERT INTO temp_created_stats (data_row_id, stat_definition_id, new_stat_for_unit_id)
        SELECT data_row_id, stat_definition_id, new_stat_for_unit_id
        FROM merged_stats;

        GET DIAGNOSTICS v_inserted_new_stat_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_statistical_variables: Inserted % new stat_for_unit records into temp_created_stats via MERGE.', p_job_id, v_inserted_new_stat_count;

        IF v_inserted_new_stat_count > 0 THEN
            v_update_pk_sql := format('UPDATE public.%I dt SET error = NULL, state = %L',
                                      v_data_table_name, 'processing'::public.import_data_state);
            v_update_pk_sep := ', ';

            FOR v_stat_def IN SELECT id, code FROM public.stat_definition
            LOOP
                v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
                IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_stat_data_cols) val
                           WHERE val->>'column_name' = v_pk_col_name AND val->>'purpose' = 'pk_id' AND (val->>'step_id')::int = v_step.id)
                THEN
                    v_update_pk_sql := v_update_pk_sql || v_update_pk_sep || format(
                        '%I = COALESCE((SELECT tcs.new_stat_for_unit_id FROM temp_created_stats tcs WHERE tcs.data_row_id = dt.row_id AND tcs.stat_definition_id = %L), dt.%I)',
                        v_pk_col_name, v_stat_def.id, v_pk_col_name 
                    );
                END IF;
            END LOOP;

            v_update_pk_sql := v_update_pk_sql || format(
                ' WHERE dt.row_id IN (SELECT DISTINCT data_row_id FROM temp_created_stats) AND dt.state != %L', 'error'
            );

            RAISE DEBUG '[Job %] process_statistical_variables: Updating _data table with final IDs for inserts: %', p_job_id, v_update_pk_sql;
            EXECUTE v_update_pk_sql;
        END IF;

        RAISE DEBUG '[Job %] process_statistical_variables: Handling REPLACES for existing stats via batch_upsert.', p_job_id;
        
        INSERT INTO temp_stat_upsert_source (
            row_id, id, valid_after, valid_to, stat_definition_id, legal_unit_id, establishment_id, -- Changed valid_from to valid_after
            value_string, value_int, value_float, value_bool, -- Add typed columns
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, -- This becomes row_id in temp_stat_upsert_source
            tbd.existing_link_id,
            tbd.valid_after, -- Changed
            tbd.valid_to,
            tbd.stat_definition_id,
            CASE 
                WHEN v_job_mode = 'legal_unit' THEN tbd.legal_unit_id
                WHEN v_job_mode IS NULL THEN tbd.legal_unit_id
                ELSE NULL 
            END,
            CASE 
                WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN tbd.establishment_id
                WHEN v_job_mode IS NULL THEN tbd.establishment_id
                ELSE NULL 
            END,
            CASE sd.type WHEN 'string' THEN tbd.stat_value ELSE NULL END,
            CASE sd.type WHEN 'int'    THEN (import.safe_cast_to_integer(tbd.stat_value)).p_value ELSE NULL END,
            CASE sd.type WHEN 'float'  THEN (import.safe_cast_to_numeric(tbd.stat_value)).p_value ELSE NULL END,
            CASE sd.type WHEN 'bool'   THEN (import.safe_cast_to_boolean(tbd.stat_value)).p_value ELSE NULL END,
            tbd.data_source_id,
            tbd.edit_by_user_id,
            tbd.edit_at,
            tbd.edit_comment -- Use tbd.edit_comment
        FROM temp_batch_data tbd
        JOIN public.stat_definition sd ON tbd.stat_definition_id = sd.id -- Join to get stat_type
        WHERE tbd.action = 'replace'; 

        GET DIAGNOSTICS v_updated_existing_stat_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_statistical_variables: Populated temp_stat_upsert_source with % rows for batch replace.', p_job_id, v_updated_existing_stat_count;

        IF v_updated_existing_stat_count > 0 THEN
            RAISE DEBUG '[Job %] process_statistical_variables: Calling batch_insert_or_replace_generic_valid_time_table for stat_for_unit. This will likely fail due to typed value columns.', p_job_id;
            -- NOTE: This call to a generic function will NOT work correctly for stat_for_unit
            -- because stat_for_unit has typed value columns (value_int, value_string etc.)
            -- and the generic function expects a single 'value' column or needs to be made aware
            -- of how to map to typed columns. This is a known limitation being addressed.
            -- For now, this part will likely error out or not update values correctly.
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'stat_for_unit',
                    p_source_schema_name => 'pg_temp', 
                    p_source_table_name => 'temp_stat_upsert_source',
                    p_unique_columns => '[]'::jsonb, 
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'created_at'], 
                    p_id_column_name => 'id'
                    -- The generic function needs to be enhanced to handle mapping of multiple value_* columns
                    -- or a specialized version for stat_for_unit is needed.
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET
                            state = %L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_stat_error', %L)
                            -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_statistical_variables: Batch replace finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_update_pk_sql := format('UPDATE public.%I dt SET error = NULL, state = %L',
                                          v_data_table_name, 'processing'::public.import_data_state);
                v_update_pk_sep := ', ';

                FOR v_stat_def IN SELECT id, code FROM public.stat_definition
                LOOP
                    v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
                    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_stat_data_cols) val
                               WHERE val->>'column_name' = v_pk_col_name AND val->>'purpose' = 'pk_id' AND (val->>'step_id')::int = v_step.id)
                    THEN
                        v_update_pk_sql := v_update_pk_sql || v_update_pk_sep || format(
                            '%I = COALESCE((SELECT tbd.existing_link_id FROM temp_batch_data tbd WHERE tbd.data_row_id = dt.row_id AND tbd.stat_definition_id = %L), dt.%I)',
                            v_pk_col_name, v_stat_def.id, v_pk_col_name 
                        );
                    END IF;
                END LOOP;

                v_update_pk_sql := v_update_pk_sql || format(' WHERE dt.row_id = ANY(%L) AND dt.state != %L', v_batch_upsert_success_row_ids, 'error');

                RAISE DEBUG '[Job %] process_statistical_variables: Updating _data table with final IDs for replaces: %', p_job_id, v_update_pk_sql;
                EXECUTE v_update_pk_sql;
            END IF;
        END IF; 

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_statistical_variables: Error during batch operation: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('process_statistical_variables_error', error_message),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_statistical_variables: Marked job as failed due to error: %', p_job_id, error_message;
        RAISE;
    END;

    -- The framework now handles advancing priority for all rows, including unprocessed and skipped rows. No update needed here.

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished operation for batch. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_stat_count, v_updated_existing_stat_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_stats;
    DROP TABLE IF EXISTS temp_stat_upsert_source;
END;
$process_statistical_variables$;


COMMIT;
