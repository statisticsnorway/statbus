```sql
CREATE OR REPLACE PROCEDURE admin.analyse_statistical_variables(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_error_check_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
BEGIN
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    -- Filter data columns relevant to this step (purpose = 'source_input' and step_id matches)
    SELECT jsonb_agg(value) INTO v_stat_data_cols
    FROM jsonb_array_elements(v_stat_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_stat_data_cols IS NULL OR jsonb_array_length(v_stat_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_statistical_variables: No stat source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE ctid = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_ctids);
         RETURN;
    END IF;

    -- Step 1: Identify and Aggregate Errors (Type Validation)
    -- Build the error checking logic dynamically based on snapshot columns and stat_definition types
    v_add_separator := FALSE;
    FOR v_col_rec IN
        SELECT
            dc.value->>'column_name' as col_name,
            sd.stat_type
        FROM jsonb_array_elements(v_stat_data_cols) dc
        JOIN public.stat_definition sd ON sd.code = dc.value->>'column_name' -- Join to get expected type
    LOOP
        IF v_add_separator THEN v_error_check_sql := v_error_check_sql || ' || '; END IF;
        v_error_check_sql := v_error_check_sql || format(
            'jsonb_build_object(%L, CASE WHEN %I IS NOT NULL AND admin.safe_cast_to_%s(%I) IS NULL THEN ''Invalid format'' ELSE NULL END)',
            v_col_rec.col_name, -- Key for error JSON
            v_col_rec.col_name, -- Column to check
            CASE v_col_rec.stat_type -- Determine safe cast function based on stat_definition type
                WHEN 'int' THEN 'integer'
                WHEN 'float' THEN 'numeric'
                WHEN 'bool' THEN 'boolean'
                ELSE 'text' -- Assume 'string' or others need no casting check
            END,
            v_col_rec.col_name -- Column to cast
        );
        v_add_separator := TRUE;
    END LOOP;

    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            ctid,
            jsonb_strip_nulls(%s) AS error_jsonb
        FROM public.%I
        WHERE ctid = ANY(%L)
    ', v_error_check_sql, v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_statistical_variables: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 2: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.ctid = err.data_ctid AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 3: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```
