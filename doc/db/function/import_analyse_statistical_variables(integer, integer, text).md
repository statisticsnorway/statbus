```sql
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$
```
