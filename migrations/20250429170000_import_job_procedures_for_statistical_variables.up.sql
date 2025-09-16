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
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_row_ids_range int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_statistical_variables$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_stat_source_cols JSONB;
    v_unpivot_sql TEXT;
    v_set_clauses TEXT;
    v_set_clauses_array TEXT[] := ARRAY[]::TEXT[];
    v_error_keys_to_clear_arr TEXT[] := ARRAY[]::TEXT[];
    v_col_rec RECORD;
    v_all_stat_raw_codes_list TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for range %s', p_job_id, p_batch_row_ids_range::text;

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list';

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'statistical_variables';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] statistical_variables target not found in snapshot', p_job_id; END IF;

    SELECT jsonb_agg(elem) INTO v_stat_source_cols FROM jsonb_array_elements(v_stat_data_cols) as elem WHERE elem->>'purpose' = 'source_input' AND (elem->>'step_id')::int = v_step.id;

    IF v_stat_source_cols IS NULL OR jsonb_array_length(v_stat_source_cols) = 0 THEN
        RAISE DEBUG '[Job %] analyse_statistical_variables: No source_input data columns found. Skipping.', p_job_id;
        v_sql := format('UPDATE public.%I SET last_completed_priority = %L WHERE row_id <@ $1', v_data_table_name, v_step.priority);
        RAISE DEBUG '[Job %] analyse_statistical_variables: Advancing priority for skipped batch with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_ids_range;
        RETURN;
    END IF;

    -- Dynamically build components for the main SQL query
    FOR v_col_rec IN
        SELECT
            replace(elem->>'column_name', '_raw', '') as code,
            elem->>'column_name' as raw_code,
            sda.type as stat_type,
            CASE sda.type
                WHEN 'int' THEN 'INTEGER' WHEN 'float' THEN 'NUMERIC' WHEN 'bool' THEN 'BOOLEAN' ELSE 'TEXT'
            END as column_type
        FROM jsonb_array_elements(v_stat_source_cols) elem
        JOIN public.stat_definition_active sda ON sda.code = replace(elem->>'column_name', '_raw', '')
    LOOP
        v_set_clauses_array := array_append(v_set_clauses_array, format('%1$I = (pivoted.values->>%2$L)::%3$s', v_col_rec.code, v_col_rec.code, v_col_rec.column_type));
        v_error_keys_to_clear_arr := array_append(v_error_keys_to_clear_arr, v_col_rec.raw_code);
    END LOOP;
    v_set_clauses := array_to_string(v_set_clauses_array, ', ');

    SELECT string_agg(format('%I', elem->>'column_name'), ', ') INTO v_all_stat_raw_codes_list FROM jsonb_array_elements(v_stat_source_cols) elem;

    SELECT string_agg(sql_part, ' UNION ALL ') INTO v_unpivot_sql
    FROM (
        SELECT format('SELECT row_id, %L AS stat_code_raw, %L AS stat_code, %L AS stat_type, %I AS stat_value_text FROM batch_data WHERE NULLIF(%I, '''') IS NOT NULL',
                      sda.code || '_raw', sda.code, sda.type, sda.code || '_raw', sda.code || '_raw') as sql_part
        FROM jsonb_array_elements(v_stat_source_cols) elem
        JOIN public.stat_definition_active sda ON sda.code = replace(elem->>'column_name', '_raw', '')
    ) AS parts;

    v_sql := format($$
        WITH
        batch_data AS (
            SELECT row_id, %1$s
            FROM public.%2$I
            WHERE row_id <@ $1 AND action IS DISTINCT FROM 'skip'
        ),
        unpivoted AS ( %3$s ),
        distinct_values AS (
            SELECT DISTINCT stat_type, stat_value_text FROM unpivoted
        ),
        casted AS (
            SELECT
                stat_type, stat_value_text,
                CASE stat_type
                    WHEN 'int' THEN (import.safe_cast_to_integer(stat_value_text)).p_value::TEXT
                    WHEN 'float' THEN (import.safe_cast_to_numeric(stat_value_text)).p_value::TEXT
                    WHEN 'bool' THEN (import.safe_cast_to_boolean(stat_value_text)).p_value::TEXT
                    ELSE stat_value_text
                END as casted_value,
                CASE stat_type
                    WHEN 'int' THEN (import.safe_cast_to_integer(stat_value_text)).p_error_message
                    WHEN 'float' THEN (import.safe_cast_to_numeric(stat_value_text)).p_error_message
                    WHEN 'bool' THEN (import.safe_cast_to_boolean(stat_value_text)).p_error_message
                    ELSE NULL
                END AS error_message
            FROM distinct_values
        ),
        pivoted AS (
            SELECT
                u.row_id,
                jsonb_object_agg(u.stat_code, c.casted_value) FILTER (WHERE c.error_message IS NULL) as values,
                jsonb_object_agg(u.stat_code_raw, c.error_message) FILTER (WHERE c.error_message IS NOT NULL) as errors
            FROM unpivoted u
            JOIN casted c ON u.stat_type = c.stat_type AND u.stat_value_text = c.stat_value_text
            GROUP BY u.row_id
        )
        UPDATE public.%2$I dt SET
            %4$s,
            state = CASE WHEN pivoted.errors IS NOT NULL THEN 'error'::public.import_data_state ELSE 'analysing'::public.import_data_state END,
            action = CASE WHEN pivoted.errors IS NOT NULL THEN 'skip'::public.import_row_action_type ELSE dt.action END,
            errors = dt.errors - %5$L::text[] || COALESCE(pivoted.errors, '{}'::jsonb),
            last_completed_priority = %6$L
        FROM pivoted
        WHERE dt.row_id = pivoted.row_id;
    $$,
        v_all_stat_raw_codes_list,    /* %1$s */
        v_data_table_name,            /* %2$I */
        v_unpivot_sql,                /* %3$s */
        v_set_clauses,                /* %4$s */
        v_error_keys_to_clear_arr,    /* %5$L */
        v_step.priority               /* %6$L */
    );

    RAISE DEBUG '[Job %] analyse_statistical_variables: Optimized batch update SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids_range;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updated % non-skipped rows.', p_job_id, v_update_count;

    v_sql := format('UPDATE public.%I SET last_completed_priority = %L WHERE row_id <@ $1 AND last_completed_priority < %L',
                   v_data_table_name, v_step.priority, v_step.priority);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids_range;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updated priority for % rows (including skipped/already updated).', p_job_id, v_skipped_update_count;

    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids_range, v_error_keys_to_clear_arr, 'analyse_statistical_variables');

    v_sql := format('SELECT COUNT(*) FROM public.%I WHERE row_id <@ $1 AND state = ''error'' AND (errors ?| %L::text[])',
                   v_data_table_name, v_error_keys_to_clear_arr);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Counting errors with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql
    INTO v_error_count USING p_batch_row_ids_range;
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished. Errors in this step for batch: %', p_job_id, v_error_count;
END;
$analyse_statistical_variables$;



-- Procedure to operate (insert/update/upsert) statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_row_ids_range int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $process_statistical_variables$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_stat_def RECORD;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_source_view_name TEXT;
    v_relevant_rows_count INT;
    v_all_stat_error_keys TEXT[];
    v_pk_id_col_name TEXT;
    v_merge_mode sql_saga.temporal_merge_mode;
    v_value_column_name TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting for range %s', p_job_id, p_batch_row_ids_range::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;
    v_job_mode := v_definition.mode;

    -- Select the correct parent unit ID column based on job mode, or NULL if not applicable.
    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'generic_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_statistical_variables: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Find step and data column details from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;
    
    -- Filter data columns for just this step
    SELECT jsonb_agg(elem) INTO v_stat_data_cols
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') as elem
    WHERE (elem->>'step_id')::int = v_step.id;

    RAISE DEBUG '[Job %] process_statistical_variables: Data columns for step % from snapshot: %', p_job_id, p_step_code, v_stat_data_cols;

    -- Loop over each statistical variable defined for this import and process it.
    FOR v_stat_def IN
        WITH source_cols AS (
            SELECT
                replace(elem->>'column_name', '_raw', '') as stat_code
            FROM jsonb_array_elements(v_stat_data_cols) elem
            WHERE elem->>'purpose' = 'source_input'
        )
        SELECT
            sda.id as stat_definition_id,
            sda.code as stat_code,
            sda.type as stat_type
        FROM source_cols sc
        JOIN public.stat_definition_active sda ON sda.code = sc.stat_code
    LOOP
        RAISE DEBUG '[Job %] process_statistical_variables: Found stat variable to process: %', p_job_id, v_stat_def;

        v_source_view_name := 'temp_stat_source_view_' || v_stat_def.stat_code;
        v_pk_id_col_name := 'stat_for_unit_' || v_stat_def.stat_code || '_id';
        -- Create a dedicated, updatable VIEW for this specific statistical variable.
        -- This view MUST contain all four `value_*` columns to match the target table's
        -- business key signature, allowing sql_saga to correctly coalesce adjacent identical records.
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.%8$I AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                %4$L::INTEGER AS stat_definition_id,
                CASE WHEN %5$L = 'int'    THEN dt.%9$I ELSE NULL END AS value_int,
                CASE WHEN %5$L = 'float'  THEN dt.%9$I ELSE NULL END AS value_float,
                CASE WHEN %5$L = 'bool'   THEN dt.%9$I ELSE NULL END AS value_bool,
                CASE WHEN %5$L = 'string' THEN dt.%9$I ELSE NULL END AS value_string,
                dt.valid_from, dt.valid_to, dt.valid_until,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%6$I dt
            WHERE dt.row_id <@ %7$L::int4multirange
              AND dt.action = 'use'
              AND dt.%9$I IS NOT NULL;
        $$,
            v_source_view_name,           /* %1$I */
            v_select_lu_id_expr,          /* %2$s */
            v_select_est_id_expr,         /* %3$s */
            v_stat_def.stat_definition_id, /* %4$L */
            v_stat_def.stat_type,           /* %5$L */
            v_data_table_name,              /* %6$I */
            p_batch_row_ids_range,          /* %7$L */
            v_pk_id_col_name,             /* %8$I */
            v_stat_def.stat_code           /* %9$I */
        );
        RAISE DEBUG '[Job %] process_statistical_variables: Creating source view for stat "%": %', p_job_id, v_stat_def.stat_code, v_sql;
        EXECUTE v_sql;

        v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
        RAISE DEBUG '[Job %] process_statistical_variables: Counting relevant rows for stat "%" with SQL: %', p_job_id, v_stat_def.stat_code, v_sql;
        EXECUTE v_sql INTO v_relevant_rows_count;
        IF v_relevant_rows_count = 0 THEN
            RAISE DEBUG '[Job %] process_statistical_variables: No usable data for stat ''%'' in this batch. Skipping.', p_job_id, v_stat_def.stat_code;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] process_statistical_variables: Calling sql_saga.temporal_merge for % rows for stat ''%''.', p_job_id, v_relevant_rows_count, v_stat_def.stat_code;

        BEGIN
            v_merge_mode := CASE v_definition.strategy
                WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
                WHEN 'replace_only' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
                WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
                WHEN 'update_only' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
                ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            END;
            RAISE DEBUG '[Job %] process_statistical_variables: Determined merge mode % for stat %', p_job_id, v_merge_mode, v_stat_def.stat_code;

            CALL sql_saga.temporal_merge(
                target_table => 'public.stat_for_unit'::regclass,
                source_table => v_source_view_name::regclass,
                identity_columns => ARRAY['id'],
                natural_identity_columns => ARRAY['stat_definition_id', 'legal_unit_id', 'establishment_id'],
                ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at', 'created_at'],
                mode => v_merge_mode,
                identity_correlation_column => 'founding_row_id',
                update_source_with_identity => true,
                update_source_with_feedback => true,
                feedback_status_column => 'merge_status',
                feedback_status_key => 'stat_' || v_stat_def.stat_code,
                feedback_error_column => 'errors',
                feedback_error_key => 'stat_' || v_stat_def.stat_code,
                source_row_id_column => 'row_id'
            );

            -- Feedback is written directly back to the data table by sql_saga, no need for manual UPDATE.

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] process_statistical_variables: Error during temporal_merge for stat ''%'': %. SQLSTATE: %', p_job_id, v_stat_def.stat_code, error_message, SQLSTATE;
            v_sql := format($$
                UPDATE public.%1$I dt
                SET errors = dt.errors || jsonb_build_object(%2$L, %3$L)
                FROM %4$I v
                WHERE dt.row_id = v.row_id;
            $$, v_data_table_name, 'stat_' || v_stat_def.stat_code, error_message, v_source_view_name);
            RAISE DEBUG '[Job %] process_statistical_variables: Marking rows as error in exception handler for stat "%" with SQL: %', p_job_id, v_stat_def.stat_code, v_sql;
            EXECUTE v_sql;
        END;
    END LOOP;

    -- Final update to set state for any rows that accumulated errors during the loop
    v_all_stat_error_keys := ARRAY(
        SELECT 'stat_' || sda.code
        FROM jsonb_array_elements(v_stat_data_cols) idc
        JOIN public.stat_definition_active sda ON sda.code = replace((idc.value->>'column_name'), '_raw', '')
        WHERE idc.value->>'purpose' = 'source_input'
    );

    v_sql := format($$
        UPDATE public.%1$I dt
        SET state = (CASE
                        WHEN dt.errors ?| %2$L THEN 'error'
                        ELSE 'processing'
                    END)::public.import_data_state
        WHERE dt.row_id <@ $1;
    $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final state update with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids_range;

    v_sql := format($$SELECT count(*) FROM public.%1$I WHERE row_id <@ $1 AND state = 'error' AND errors ?| %2$L $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final error count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_error_count USING p_batch_row_ids_range;

    v_sql := format('SELECT count(*) FROM public.%1$I WHERE row_id <@ $1', v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Final total count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_update_count USING p_batch_row_ids_range;
    v_update_count := v_update_count - v_error_count;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished for step %. Total rows affected: %, Errors: %',
        p_job_id, p_step_code, v_update_count, v_error_count;
END;
$process_statistical_variables$;


COMMIT;
