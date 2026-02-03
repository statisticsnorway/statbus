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
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
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
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list';

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'statistical_variables';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] statistical_variables target not found in snapshot', p_job_id; END IF;

    SELECT jsonb_agg(elem) INTO v_stat_source_cols FROM jsonb_array_elements(v_stat_data_cols) as elem WHERE elem->>'purpose' = 'source_input' AND (elem->>'step_id')::int = v_step.id;

    IF v_stat_source_cols IS NULL OR jsonb_array_length(v_stat_source_cols) = 0 THEN
        RAISE DEBUG '[Job %] analyse_statistical_variables: No source_input data columns found for this definition. Skipping step.', p_job_id;
        v_sql := format($$UPDATE public.%1$I dt SET last_completed_priority = %2$L
                           WHERE dt.batch_seq = $1
                             AND dt.last_completed_priority < %2$L
                          $$, v_data_table_name, v_step.priority);
        RAISE DEBUG '[Job %] analyse_statistical_variables: Advancing priority for skipped batch with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        RETURN;
    END IF;

    -- Dynamically build components for the decomposed query
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
        SELECT format('SELECT row_id, %L AS stat_code_raw, %L AS stat_code, %L AS stat_type, %I AS stat_value_text FROM t_batch_data WHERE NULLIF(%I, '''') IS NOT NULL',
                      sda.code || '_raw', sda.code, sda.type, sda.code || '_raw', sda.code || '_raw') as sql_part
        FROM jsonb_array_elements(v_stat_source_cols) elem
        JOIN public.stat_definition_active sda ON sda.code = replace(elem->>'column_name', '_raw', '')
    ) AS parts;

    -- Decomposed query approach for performance
    -- Step 1: Select batch into a temp table using the performant unnest/JOIN pattern.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
                       SELECT dt.row_id, %1$s
                       FROM public.%2$I dt
                       WHERE dt.batch_seq = $1
                         AND dt.action IS DISTINCT FROM 'skip'
                    $$, v_all_stat_raw_codes_list, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    -- Step 2: Unpivot the raw data from the batch.
    IF to_regclass('pg_temp.t_unpivoted') IS NOT NULL THEN DROP TABLE t_unpivoted; END IF;
    v_sql := format('CREATE TEMP TABLE t_unpivoted ON COMMIT DROP AS %s', v_unpivot_sql);
    EXECUTE v_sql;

    -- Step 3: Get distinct values to minimize casting operations.
    IF to_regclass('pg_temp.t_distinct_values') IS NOT NULL THEN DROP TABLE t_distinct_values; END IF;
    CREATE TEMP TABLE t_distinct_values ON COMMIT DROP AS SELECT DISTINCT stat_type, stat_value_text FROM t_unpivoted;

    -- Step 4: Perform casting on the small set of distinct values.
    IF to_regclass('pg_temp.t_casted') IS NOT NULL THEN DROP TABLE t_casted; END IF;
    CREATE TEMP TABLE t_casted ON COMMIT DROP AS
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
    FROM t_distinct_values;

    -- Step 5: Pivot the casted data and errors back by row_id.
    IF to_regclass('pg_temp.t_pivoted') IS NOT NULL THEN DROP TABLE t_pivoted; END IF;
    CREATE TEMP TABLE t_pivoted ON COMMIT DROP AS
    SELECT
        u.row_id,
        jsonb_object_agg(u.stat_code, c.casted_value) FILTER (WHERE c.error_message IS NULL) as values,
        jsonb_object_agg(u.stat_code_raw, c.error_message) FILTER (WHERE c.error_message IS NOT NULL) as errors
    FROM t_unpivoted u
    JOIN t_casted c ON u.stat_type = c.stat_type AND u.stat_value_text = c.stat_value_text
    GROUP BY u.row_id;

    -- Step 6: Perform the final, simple UPDATE by joining against the pivoted temp table.
    BEGIN
        v_sql := format($$UPDATE public.%1$I dt SET
                %2$s,
                state = CASE WHEN COALESCE(pivoted.errors, '{}'::jsonb) != '{}'::jsonb THEN 'error'::public.import_data_state ELSE 'analysing'::public.import_data_state END,
                action = CASE WHEN COALESCE(pivoted.errors, '{}'::jsonb) != '{}'::jsonb THEN 'skip'::public.import_row_action_type ELSE dt.action END,
                errors = dt.errors - %3$L::text[] || COALESCE(pivoted.errors, '{}'::jsonb),
                last_completed_priority = %4$L
            FROM t_pivoted pivoted
            WHERE dt.row_id = pivoted.row_id
        $$,
            v_data_table_name,            /* %1$I */
            v_set_clauses,                /* %2$s */
            v_error_keys_to_clear_arr,    /* %3$L */
            v_step.priority               /* %4$L */
        );
        RAISE DEBUG '[Job %] analyse_statistical_variables: Decomposed batch update SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated % non-skipped rows via decomposed method.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_statistical_variables: Error during decomposed batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_statistical_variables_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    v_sql := format($$UPDATE public.%1$I dt SET last_completed_priority = %2$L
                       WHERE dt.batch_seq = $1
                         AND dt.last_completed_priority < %2$L
                      $$, v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updated priority for % rows (including skipped/already updated).', p_job_id, v_skipped_update_count;

    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_statistical_variables');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_statistical_variables: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    v_sql := format('SELECT COUNT(*) FROM public.%I dt WHERE dt.batch_seq = $1 AND dt.state = ''error'' AND (dt.errors ?| %L::text[])',
                   v_data_table_name, v_error_keys_to_clear_arr);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Counting errors with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql
    INTO v_error_count USING p_batch_seq;
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished. Errors in this step for batch: %', p_job_id, v_error_count;
END;
$analyse_statistical_variables$;



-- Procedure to operate (insert/update/upsert) statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
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
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting for batch_seq %', p_job_id, p_batch_seq;

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
                dt.%7$I AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                %4$L::INTEGER AS stat_definition_id,
                CASE WHEN %5$L = 'int'    THEN dt.%8$I ELSE NULL END AS value_int,
                CASE WHEN %5$L = 'float'  THEN dt.%8$I ELSE NULL END AS value_float,
                CASE WHEN %5$L = 'bool'   THEN dt.%8$I ELSE NULL END AS value_bool,
                CASE WHEN %5$L = 'string' THEN dt.%8$I ELSE NULL END AS value_string,
                dt.valid_from, dt.valid_to, dt.valid_until,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%6$I dt
            WHERE dt.batch_seq = %9$L
              AND dt.action = 'use'
              AND dt.%8$I IS NOT NULL;
        $$,
            v_source_view_name,           /* %1$I */
            v_select_lu_id_expr,          /* %2$s */
            v_select_est_id_expr,         /* %3$s */
            v_stat_def.stat_definition_id, /* %4$L */
            v_stat_def.stat_type,           /* %5$L */
            v_data_table_name,              /* %6$I */
            v_pk_id_col_name,             /* %7$I */
            v_stat_def.stat_code,          /* %8$I */
            p_batch_seq                    /* %9$L */
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
                WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
                WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
                WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
                ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            END;
            RAISE DEBUG '[Job %] process_statistical_variables: Determined merge mode % for stat %', p_job_id, v_merge_mode, v_stat_def.stat_code;

            CALL sql_saga.temporal_merge(
                target_table => 'public.stat_for_unit'::regclass,
                source_table => v_source_view_name::regclass,
                primary_identity_columns => ARRAY['id'],
                natural_identity_columns => ARRAY['stat_definition_id', 'legal_unit_id', 'establishment_id'],
                mode => v_merge_mode,
                row_id_column => 'row_id',
                founding_id_column => 'founding_row_id',
                update_source_with_identity => true,
                update_source_with_feedback => true,
                feedback_status_column => 'merge_status',
                feedback_status_key => 'stat_' || v_stat_def.stat_code,
                feedback_error_column => 'errors',
                feedback_error_key => 'stat_' || v_stat_def.stat_code
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

    -- Only update rows with action = 'use' to satisfy CHECK constraint:
    -- state = 'processing' requires action = 'use' AND batch_seq IS NOT NULL
    v_sql := format($$
        UPDATE public.%1$I dt
        SET state = (CASE
                        WHEN dt.errors ?| %2$L THEN 'error'
                        ELSE 'processing'
                    END)::public.import_data_state
        WHERE dt.batch_seq = $1 AND dt.action = 'use';
    $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final state update with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    v_sql := format($$SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND dt.errors ?| %2$L $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final error count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_error_count USING p_batch_seq;

    v_sql := format('SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1', v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Final total count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_update_count USING p_batch_seq;
    v_update_count := v_update_count - v_error_count;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished for step %. Total rows affected: %, Errors: %',
        p_job_id, p_step_code, v_update_count, v_error_count;
END;
$process_statistical_variables$;


COMMIT;
