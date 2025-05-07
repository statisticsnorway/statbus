-- Migration: implement_valid_time_procedures
-- Implements the analyse procedures for the valid_time_from_context and valid_time_from_source import steps.

BEGIN;

-- Helper function for safe date casting
CREATE OR REPLACE FUNCTION admin.safe_cast_to_date(p_text_date TEXT)
RETURNS DATE LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_date IS NULL OR p_text_date = '' THEN
        RETURN NULL;
    END IF;
    -- Attempt common ISO and other formats
    RETURN p_text_date::DATE;
EXCEPTION WHEN others THEN
    RAISE DEBUG 'Invalid date format: "%". Returning NULL.', p_text_date;
    RETURN NULL;
END;
$$;

-- Procedure to analyse valid_time derived from job context (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_valid_time_from_context(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_valid_time_from_context$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'valid_time_from_context';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time_from_context target not found', p_job_id;
    END IF;

    -- Step 1: Batch Update derived_valid_from/to from job defaults
    v_sql := format($$
        UPDATE public.%I dt SET
            derived_valid_from = %L::DATE,
            derived_valid_to = %L::DATE,
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.row_id = ANY(%L);
    $$, v_data_table_name, v_job.default_valid_from, v_job.default_valid_to, v_step.priority, 'analysing', p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Updating derived dates: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Finished analysis for batch.', p_job_id;
END;
$analyse_valid_time_from_context$;


-- Procedure to analyse valid_time provided in source data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_valid_time_from_source(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_valid_time_from_source$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time_from_source (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'valid_time_from_source';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time_from_source target not found', p_job_id;
    END IF;

    -- Step 1: Batch Update derived_valid_from/to using safe casting from source TEXT columns
    v_sql := format($$
        UPDATE public.%I dt SET
            derived_valid_from = admin.safe_cast_to_date(dt.valid_from), -- valid_from is source TEXT
            derived_valid_to = admin.safe_cast_to_date(dt.valid_to)     -- valid_to is source TEXT
        WHERE dt.row_id = ANY(%L);
    $$, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Batch updating derived dates from source: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            row_id, -- Select row_id from the main data table
            jsonb_strip_nulls(
                jsonb_build_object('valid_from_source', CASE WHEN valid_from IS NOT NULL AND derived_valid_from IS NULL THEN 'Invalid format' ELSE NULL END) || -- Check source 'valid_from' against 'derived_valid_from'
                jsonb_build_object('valid_to_source', CASE WHEN valid_to IS NOT NULL AND derived_valid_to IS NULL THEN 'Invalid format' ELSE NULL END)       -- Check source 'valid_to' against 'derived_valid_to'
            ) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L) -- Filter by row_id from the main data table
     $$, v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_valid_time_from_source: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
    $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb; -- Corrected to data_row_id
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 4: Batch Update Success Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - 'valid_from_source' - 'valid_to_source') = '{}'::jsonb THEN NULL ELSE (dt.error - 'valid_from_source' - 'valid_to_source') END, -- Clear only this step's error keys
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L);
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[])); -- Changed TID[] to BIGINT[]
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_valid_time_from_source (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_valid_time_from_source$;

-- Note: No process_valid_time_from_source procedure is needed.
-- The typed_valid_from/to columns are used by the main unit processing procedures (legal_unit, establishment).

COMMIT;
