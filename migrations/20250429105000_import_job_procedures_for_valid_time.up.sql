-- Implements the analyse procedures for the valid_time_from_context and valid_time_from_source import steps.

BEGIN;

-- Helper function for safe date casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_date(p_text_date TEXT)
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
CREATE OR REPLACE PROCEDURE import.analyse_valid_time_from_context(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
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

    -- Step 1: Batch Update derived_valid_from/to and derived_valid_after from job defaults for non-skipped rows
    v_sql := format($$
        UPDATE public.%I dt SET
            derived_valid_after = CASE WHEN %L::DATE IS NOT NULL THEN %L::DATE - INTERVAL '1 day' ELSE NULL END, -- Calculate derived_valid_after
            derived_valid_from = %L::DATE,
            derived_valid_to = %L::DATE,
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$, v_data_table_name, v_job.default_valid_from, v_job.default_valid_from, v_job.default_valid_from, v_job.default_valid_to, v_step.priority, 'analysing', p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Updating derived dates for non-skipped rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Marked % non-skipped rows as success for this target.', p_job_id, v_update_count;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Finished analysis for batch.', p_job_id;
END;
$analyse_valid_time_from_context$;


-- Procedure to analyse valid_time provided in source data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_valid_time_from_source(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_valid_time_from_source$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from_source', 'valid_to_source'];
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

    -- Single-pass batch update for casting, state, error, and priority
    v_sql := format($$
        UPDATE public.%I dt SET
            derived_valid_from = import.safe_cast_to_date(dt.valid_from),
            derived_valid_after = import.safe_cast_to_date(dt.valid_from) - INTERVAL '1 day',
            derived_valid_to = import.safe_cast_to_date(dt.valid_to),
            state = CASE
                        WHEN dt.valid_from IS NOT NULL AND import.safe_cast_to_date(dt.valid_from) IS NULL THEN 'error'::public.import_data_state
                        WHEN dt.valid_to IS NOT NULL AND import.safe_cast_to_date(dt.valid_to) IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN dt.valid_from IS NOT NULL AND import.safe_cast_to_date(dt.valid_from) IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_from_source', 'Invalid format')
                        WHEN dt.valid_to IS NOT NULL AND import.safe_cast_to_date(dt.valid_to) IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_to_source', 'Invalid format')
                        ELSE
                            CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            last_completed_priority = CASE
                                        WHEN (dt.valid_from IS NOT NULL AND import.safe_cast_to_date(dt.valid_from) IS NULL) OR
                                             (dt.valid_to IS NOT NULL AND import.safe_cast_to_date(dt.valid_to) IS NULL)
                                        THEN dt.last_completed_priority -- Preserve existing LCP on error
                                        ELSE %s -- v_step.priority (success)
                                      END
        WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$,
        v_data_table_name,
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr, -- For error CASE (clear)
        v_step.priority,                                     -- For last_completed_priority CASE (success part)
        p_batch_row_ids
    );
    RAISE DEBUG '[Job %] analyse_valid_time_from_source: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
        ', v_data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time_from_source: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        -- Estimate error count
        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_valid_time_from_source: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_valid_time_from_source: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_valid_time_from_source_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_valid_time_from_source: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_valid_time_from_source (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_valid_time_from_source$;

-- Note: No process_valid_time_from_source procedure is needed.
-- The typed_valid_from/to columns are used by the main unit processing procedures (legal_unit, establishment).

COMMIT;
