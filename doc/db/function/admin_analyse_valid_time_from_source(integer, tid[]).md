```sql
CREATE OR REPLACE PROCEDURE admin.analyse_valid_time_from_source(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time_from_source (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'valid_time_from_source';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time_from_source target not found', p_job_id;
    END IF;

    -- Step 1: Batch Update typed_valid_from/to using safe casting
    v_sql := format('
        UPDATE public.%I dt SET
            typed_valid_from = admin.safe_cast_to_date(dt.valid_from),
            typed_valid_to = admin.safe_cast_to_date(dt.valid_to)
        WHERE dt.ctid = ANY(%L);
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Batch updating typed dates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            data_ctid,
            jsonb_strip_nulls(
                jsonb_build_object(''valid_from'', CASE WHEN valid_from IS NOT NULL AND typed_valid_from IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''valid_to'', CASE WHEN valid_to IS NOT NULL AND typed_valid_to IS NULL THEN ''Invalid format'' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE data_ctid = ANY(%L)
    ', v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_valid_time_from_source: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.ctid = err.data_ctid AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 4: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_valid_time_from_source (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```
