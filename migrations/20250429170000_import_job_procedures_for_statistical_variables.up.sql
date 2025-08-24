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
         EXECUTE format($$UPDATE public.%1$I SET last_completed_priority = %2$L WHERE row_id = ANY($1)$$,
                        v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
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
          AND (idc.value->>'step_id')::int = v_step.id -- ONLY consider columns for this step
    LOOP
        IF v_add_separator THEN
            v_error_conditions_sql := v_error_conditions_sql || ' OR ';
            v_error_json_sql := v_error_json_sql || ' || ';
        END IF;
        
        v_error_conditions_sql := v_error_conditions_sql || format(
            '(dt.%1$I IS NOT NULL AND (import.safe_cast_to_%2$s(dt.%1$I)).p_error_message IS NOT NULL)', -- Check p_error_message
            v_col_rec.col_name, /* %1$I */
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END /* %2$s */
        );
        
        v_error_json_sql := v_error_json_sql || format(
            'jsonb_build_object(%1$L, CASE WHEN dt.%2$I IS NOT NULL THEN (import.safe_cast_to_%3$s(dt.%2$I)).p_error_message ELSE NULL END)', -- Use p_error_message
            v_col_rec.col_name, /* %1$L */
            v_col_rec.col_name, /* %2$I */
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END /* %3$s */
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
        UPDATE public.%1$I dt SET
            -- Determine state first
            state = CASE
                        WHEN %2$s THEN 'error'::public.import_data_state -- Error condition for this step
                        ELSE 'analysing'::public.import_data_state -- No error from this step
                    END,
            -- Then determine action based on the new state or existing action
            action = CASE
                        WHEN %2$s THEN 'skip'::public.import_row_action_type -- If this step causes an error, action becomes 'skip'
                        ELSE dt.action -- Otherwise, preserve existing action
                     END,
            error = CASE
                        WHEN %2$s THEN COALESCE(dt.error, '{}'::jsonb) || jsonb_strip_nulls(%3$s) -- Error condition for this step
                        ELSE CASE WHEN (dt.error - %4$L) = '{}'::jsonb THEN NULL ELSE (dt.error - %4$L) END -- Clear errors specific to this step if no new error
                    END,
            last_completed_priority = %5$L -- Always v_step.priority
        WHERE dt.row_id = ANY($1) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$,
        v_data_table_name /* %1$I */,
        v_error_conditions_sql /* %2$s */, -- Reused for state/action/error conditions
        v_error_json_sql /* %3$s */,       -- Error JSON to append
        v_error_keys_to_clear_list /* %4$L */, -- Keys to clear from error JSON
        v_step.priority /* %5$L */            -- last_completed_priority (always this step's priority)
    );

    RAISE DEBUG '[Job %] analyse_statistical_variables: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (error ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_list /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
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

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_list, 'analyse_statistical_variables');

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
    v_batch_errors JSONB[] := ARRAY[]::JSONB[];
    v_pk_col_name TEXT;
    v_stat_def RECORD;
    v_update_pk_sql TEXT := '';
    v_update_pk_sep TEXT := '';
    v_job_mode public.import_mode;
    v_excluded_unit_id_cols TEXT[];
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_update_count INT;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

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
          AND (idc.value->>'step_id')::int = v_step.id -- ONLY consider columns for this step
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        -- Ensure we only try to unpivot if the column actually has a non-empty, non-whitespace value.
        -- The IS NOT NULL check is good, but char_length(trim(...)) > 0 is more robust for TEXT fields that might contain only whitespace.
        v_unpivot_sql := v_unpivot_sql || format($$SELECT %1$L AS stat_code, dt.%2$I AS stat_value, dt.row_id AS data_row_id_from_source FROM public.%3$I dt WHERE dt.%4$I IS NOT NULL AND char_length(trim(dt.%4$I)) > 0 AND dt.row_id = ANY($1) AND dt.action != 'skip'$$, 
                                                 v_col_rec.col_name, /* %1$L */
                                                 v_col_rec.col_name, /* %2$I */
                                                 v_data_table_name,  /* %3$I */
                                                 v_col_rec.col_name  /* %4$I */
                                                );
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
         RAISE DEBUG '[Job %] process_statistical_variables: No stat data columns found in snapshot for target % or all rows skipped. Skipping operation.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY($1)$$,
                        v_data_table_name, v_step.priority) USING p_batch_row_ids;
         RETURN;
    END IF;

    v_job_mode := v_definition.mode;

    -- Determine which unit ID columns to exclude based on the import mode.
    -- This is crucial to prevent violating the check constraint on stat_for_unit,
    -- which ensures only one unit FK is set per row. The calling procedure has
    -- the business context that the generic planner lacks.
    CASE v_job_mode
        WHEN 'legal_unit' THEN
            v_excluded_unit_id_cols := ARRAY['establishment_id', 'enterprise_id', 'group_id'];
        WHEN 'establishment_formal', 'establishment_informal' THEN
            v_excluded_unit_id_cols := ARRAY['legal_unit_id', 'enterprise_id', 'group_id'];
        WHEN 'enterprise' THEN
            v_excluded_unit_id_cols := ARRAY['legal_unit_id', 'establishment_id', 'group_id'];
        WHEN 'enterprise_group' THEN
            v_excluded_unit_id_cols := ARRAY['legal_unit_id', 'establishment_id', 'enterprise_id'];
        ELSE
            -- For generic_unit or other modes, don't exclude any unit columns by default.
            v_excluded_unit_id_cols := '{}'::TEXT[];
    END CASE;

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

    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER,
        founding_row_id INTEGER,
        legal_unit_id INT,
        establishment_id INT,
        valid_after DATE, -- Added
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        stat_definition_id INT,
        stat_value TEXT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        action public.import_row_action_type, 
        PRIMARY KEY (data_row_id, stat_definition_id) 
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, legal_unit_id, establishment_id, valid_after, valid_from, valid_to, data_source_id,
            stat_definition_id, stat_value, edit_by_user_id, edit_at, edit_comment, action
        )
        SELECT
            up.data_row_id_from_source,
            dt.founding_row_id,
            %2$s, 
            %3$s, 
            dt.derived_valid_after,
            dt.derived_valid_from, 
            dt.derived_valid_to,   
            dt.data_source_id,
            sd.id,
            up.stat_value,
            dt.edit_by_user_id,
            dt.edit_at,
            dt.edit_comment,
            dt.action 
        FROM ( %1$s ) up
        JOIN public.%4$I dt ON up.data_row_id_from_source = dt.row_id
        JOIN public.stat_definition sd ON sd.code = up.stat_code;
    $$, v_unpivot_sql /* %1$s (now a subquery) */, v_select_lu_id_expr /* %2$s */, v_select_est_id_expr /* %3$s */, v_data_table_name /* %4$I */);
    RAISE DEBUG '[Job %] process_statistical_variables: Fetching and unpivoting batch data (v_sql): %', p_job_id, v_sql;

    EXECUTE v_sql USING p_batch_row_ids; -- Parameterize batch ids

    -- Debugging block to inspect temp_batch_data
    DECLARE
        tbd_row_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO tbd_row_count FROM temp_batch_data;
        RAISE DEBUG '[Job %] process_statistical_variables: temp_batch_data populated with % rows.', p_job_id, tbd_row_count;
    END;
    -- End Debugging block


    CREATE TEMP TABLE temp_created_stats (
        data_row_id INTEGER,
        stat_definition_id INT,
        new_stat_for_unit_id INT NOT NULL,
        PRIMARY KEY (data_row_id, stat_definition_id)
    ) ON COMMIT DROP;

    -- Create temp source table for set-based upsert (for replaces) *before* the inner BEGIN block
    CREATE TEMP TABLE temp_stat_upsert_source (
        row_id INTEGER, 
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
        RAISE DEBUG '[Job %] process_statistical_variables: Handling stats using generic set-based functions.', p_job_id;

        INSERT INTO temp_stat_upsert_source (
            row_id, valid_after, valid_to, stat_definition_id, legal_unit_id, establishment_id,
            value_string, value_int, value_float, value_bool,
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id,
            tbd.valid_after,
            tbd.valid_to,
            tbd.stat_definition_id,
            tbd.legal_unit_id,
            tbd.establishment_id,
            CASE sd.type WHEN 'string' THEN tbd.stat_value ELSE NULL END,
            CASE sd.type WHEN 'int'    THEN (import.safe_cast_to_integer(tbd.stat_value)).p_value ELSE NULL END,
            CASE sd.type WHEN 'float'  THEN (import.safe_cast_to_numeric(tbd.stat_value)).p_value ELSE NULL END,
            CASE sd.type WHEN 'bool'   THEN (import.safe_cast_to_boolean(tbd.stat_value)).p_value ELSE NULL END,
            tbd.data_source_id,
            tbd.edit_by_user_id,
            tbd.edit_at,
            tbd.edit_comment
        FROM temp_batch_data tbd
        JOIN public.stat_definition sd ON tbd.stat_definition_id = sd.id;

        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_statistical_variables: Populated temp_stat_upsert_source with % rows.', p_job_id, v_update_count;

        DECLARE
            v_entity_id_cols TEXT[];
        BEGIN
            IF v_job_mode = 'legal_unit' THEN
                v_entity_id_cols := ARRAY['stat_definition_id', 'legal_unit_id'];
            ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
                v_entity_id_cols := ARRAY['stat_definition_id', 'establishment_id'];
            ELSE -- Covers NULL mode for stats_update jobs
                v_entity_id_cols := ARRAY['stat_definition_id', 'legal_unit_id', 'establishment_id'];
            END IF;
            RAISE DEBUG '[Job %] process_statistical_variables: Using entity ID columns: %', p_job_id, v_entity_id_cols;

            FOR v_batch_upsert_result IN
                SELECT * FROM import.temporal_merge(
                    p_target_schema_name       => 'public',
                    p_target_table_name        => 'stat_for_unit',
                    p_source_schema_name       => 'pg_temp',
                    p_source_table_name        => 'temp_stat_upsert_source',
                    p_entity_id_column_names   => v_entity_id_cols,
                    p_mode                     => CASE v_strategy
                                                      WHEN 'insert_or_replace' THEN 'upsert_replace'::import.set_operation_mode
                                                      WHEN 'insert_or_update'  THEN 'upsert_patch'::import.set_operation_mode
                                                      WHEN 'replace_only'      THEN 'replace_only'::import.set_operation_mode
                                                      WHEN 'update_only'       THEN 'patch_only'::import.set_operation_mode
                                                      WHEN 'insert_only'       THEN 'insert_only'::import.set_operation_mode
                                                  END,
                    p_source_row_ids           => NULL, -- Process all rows from the temp source
                    p_ephemeral_columns        => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_insert_defaulted_columns => ARRAY['id', 'created_at'] || v_excluded_unit_id_cols
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    v_batch_errors := array_append(v_batch_errors, jsonb_build_object('source_row_id', v_batch_upsert_result.source_row_id, 'error_message', v_batch_upsert_result.error_message));
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;
        END;

        v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
        v_inserted_new_stat_count := array_length(v_batch_upsert_success_row_ids, 1);
        RAISE DEBUG '[Job %] process_statistical_variables: Set-based upsert finished. Success: %, Errors: %', p_job_id, v_inserted_new_stat_count, v_error_count;

        IF v_error_count > 0 THEN
            -- Mark the specific rows that failed
            EXECUTE format('UPDATE public.%I SET state = %L, error = %L WHERE row_id = ANY($1)',
                v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('process_statistical_variables_error', 'Failed during set-based temporal processing.')
            ) USING v_batch_upsert_error_row_ids;
            -- Then, fail the entire batch by raising an exception
            RAISE EXCEPTION '[Job %] process_statistical_variables: Failed to process % statistical variable rows in batch. Errors: %', p_job_id, v_error_count, v_batch_errors;
        END IF;

        IF v_inserted_new_stat_count > 0 THEN
            EXECUTE format('UPDATE public.%I SET state = %L WHERE row_id = ANY($1)',
                v_data_table_name, 'processing'::public.import_data_state
            ) USING v_batch_upsert_success_row_ids;
        END IF;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_statistical_variables: Error during set-based upsert operation: %', p_job_id, error_message;
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

    IF to_regclass('pg_temp.temp_batch_data') IS NOT NULL THEN DROP TABLE temp_batch_data; END IF;
    IF to_regclass('pg_temp.temp_created_stats') IS NOT NULL THEN DROP TABLE temp_created_stats; END IF;
    IF to_regclass('pg_temp.temp_stat_upsert_source') IS NOT NULL THEN DROP TABLE temp_stat_upsert_source; END IF;
END;
$process_statistical_variables$;


COMMIT;
