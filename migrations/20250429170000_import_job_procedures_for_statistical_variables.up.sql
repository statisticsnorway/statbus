-- Migration: import_job_procedures_for_stats
-- Implements the analyse and operation procedures for the statistical_variables import target.

BEGIN;

-- Helper function for safe integer casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_integer(p_text_value TEXT)
RETURNS INTEGER LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_value::INTEGER;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid integer format: "%". Returning NULL.', p_text_value;
    RETURN NULL;
END;
$$;

-- Helper function for safe boolean casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_boolean(p_text_value TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_value::BOOLEAN;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid boolean format: "%". Returning NULL.', p_text_value;
    RETURN NULL;
END;
$$;

-- Procedure to analyse statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_statistical_variables$
DECLARE
    v_job public.import_job;
    v_step RECORD;
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

    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    SELECT jsonb_agg(value) INTO v_stat_data_cols
    FROM jsonb_array_elements(v_stat_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_stat_data_cols IS NULL OR jsonb_array_length(v_stat_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_statistical_variables: No stat source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    v_add_separator := FALSE;
    FOR v_col_rec IN
        SELECT
            dc.value->>'column_name' as col_name,
            sda.type 
        FROM jsonb_array_elements(v_stat_data_cols) dc
        JOIN public.stat_definition_active sda ON sda.code = dc.value->>'column_name'
    LOOP
        IF v_add_separator THEN 
            v_error_conditions_sql := v_error_conditions_sql || ' OR ';
            v_error_json_sql := v_error_json_sql || ' || ';
        END IF;
        
        v_error_conditions_sql := v_error_conditions_sql || format(
            '(dt.%I IS NOT NULL AND import.safe_cast_to_%s(dt.%I) IS NULL)',
            v_col_rec.col_name,
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END,
            v_col_rec.col_name
        );
        
        v_error_json_sql := v_error_json_sql || format(
            'jsonb_build_object(%L, CASE WHEN dt.%I IS NOT NULL AND import.safe_cast_to_%s(dt.%I) IS NULL THEN ''Invalid format'' ELSE NULL END)',
            v_col_rec.col_name,
            v_col_rec.col_name,
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END,
            v_col_rec.col_name
        );
        v_error_keys_to_clear_list := array_append(v_error_keys_to_clear_list, v_col_rec.col_name);
        v_add_separator := TRUE;
    END LOOP;

    IF v_error_conditions_sql = '' THEN -- Should not happen if v_stat_data_cols is not empty
        v_error_conditions_sql := 'FALSE';
        v_error_json_sql := '''{}''::jsonb';
    END IF;

    v_sql := format($$
        UPDATE public.%I dt SET
            state = CASE
                        WHEN %s THEN 'error'::public.import_data_state -- Error condition
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN %s THEN COALESCE(dt.error, '{}'::jsonb) || jsonb_strip_nulls(%s) -- Error condition
                        ELSE CASE WHEN (dt.error - %L) = '{}'::jsonb THEN NULL ELSE (dt.error - %L) END
                    END,
            last_completed_priority = CASE
                                        WHEN %s THEN %L::INTEGER -- Error condition: v_step.priority - 1
                                        ELSE %L::INTEGER -- Success: v_step.priority
                                      END
        WHERE dt.row_id = ANY(%L) AND dt.action != 'skip'; -- Exclude skipped rows
    $$,
        v_data_table_name,
        v_error_conditions_sql, -- For state CASE
        v_error_conditions_sql, v_error_json_sql, -- For error CASE (add)
        v_error_keys_to_clear_list, v_error_keys_to_clear_list, -- For error CASE (clear)
        v_error_conditions_sql, v_step.priority - 1, v_step.priority, -- For last_completed_priority CASE
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
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_statistical_variables$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
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
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_pk_col_name TEXT;
    v_stat_def RECORD;
    v_update_pk_sql TEXT := '';
    v_update_pk_sep TEXT := '';
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 
    v_definition := v_job.definition_snapshot->'import_definition'; 
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; 

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' OR
       v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition or import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_stat_data_cols) value 
                     WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input' 
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format($$SELECT %L AS stat_code, dt.%I AS stat_value, dt.row_id AS data_row_id_from_source FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L) AND dt.action != 'skip'$$, 
                                                 v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_row_ids);
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
         RAISE DEBUG '[Job %] process_statistical_variables: No stat data columns found in snapshot for target % or all rows skipped. Skipping operation.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

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
        data_row_id BIGINT, 
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
    RAISE DEBUG '[Job %] process_statistical_variables: Fetching and unpivoting batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

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
        data_row_id BIGINT,
        stat_definition_id INT,
        new_stat_for_unit_id INT NOT NULL,
        PRIMARY KEY (data_row_id, stat_definition_id)
    ) ON COMMIT DROP;

    -- Create temp source table for batch upsert (for replaces) *before* the inner BEGIN block
    CREATE TEMP TABLE temp_stat_upsert_source (
        data_row_id BIGINT, 
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
        PRIMARY KEY (data_row_id, stat_definition_id) 
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
                    CASE sfi.stat_type WHEN 'int'    THEN import.safe_cast_to_integer(sfi.stat_value) ELSE NULL END,
                    CASE sfi.stat_type WHEN 'float'  THEN import.safe_cast_to_numeric(sfi.stat_value) ELSE NULL END,
                    CASE sfi.stat_type WHEN 'bool'   THEN import.safe_cast_to_boolean(sfi.stat_value) ELSE NULL END,
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
            v_update_pk_sql := format('UPDATE public.%I dt SET last_completed_priority = %L, error = NULL, state = %L',
                                      v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
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
            data_row_id, id, valid_after, valid_to, stat_definition_id, legal_unit_id, establishment_id, -- Changed valid_from to valid_after
            value_string, value_int, value_float, value_bool, -- Add typed columns
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, 
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
            CASE sd.type WHEN 'int'    THEN import.safe_cast_to_integer(tbd.stat_value) ELSE NULL END,
            CASE sd.type WHEN 'float'  THEN import.safe_cast_to_numeric(tbd.stat_value) ELSE NULL END,
            CASE sd.type WHEN 'bool'   THEN import.safe_cast_to_boolean(tbd.stat_value) ELSE NULL END,
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
                    p_source_row_id_column_name => 'data_row_id',
                    p_unique_columns => '[]'::jsonb, 
                    p_temporal_columns => ARRAY['valid_after', 'valid_to'], -- Changed
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'], 
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
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_stat_error', %L),
                            last_completed_priority = %L
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_statistical_variables: Batch replace finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_update_pk_sql := format('UPDATE public.%I dt SET last_completed_priority = %L, error = NULL, state = %L',
                                          v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
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

     v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action != 'skip'
          AND dt.state != 'error'
          AND NOT EXISTS (SELECT 1 FROM temp_created_stats tcs WHERE tcs.data_row_id = dt.row_id) 
          AND NOT EXISTS (SELECT 1 FROM temp_stat_upsert_source tsus WHERE tsus.data_row_id = dt.row_id); 
    $$, v_data_table_name, v_step.priority, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_statistical_variables: Updating priority for unprocessed rows: %', p_job_id, v_sql;
    EXECUTE v_sql;

    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_job.data_table_name, v_step.priority, p_batch_row_ids);

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished operation for batch. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_stat_count, v_updated_existing_stat_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_stats;
    DROP TABLE IF EXISTS temp_stat_upsert_source;
END;
$process_statistical_variables$;


COMMIT;
