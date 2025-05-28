-- Implements the analyse procedures for the valid_time_from_context and valid_time_from_source import steps.

BEGIN;

-- Helper function for safe date casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_date(
    IN p_text_date TEXT,
    OUT p_value DATE,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_date IS NULL OR p_text_date = '' THEN
        RETURN; -- p_value and p_error_message remain NULL
    END IF;

    BEGIN
        p_value := p_text_date::DATE;
    EXCEPTION
        WHEN invalid_datetime_format THEN
            p_error_message := 'Invalid date format: ''' || p_text_date || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_date || ''' to date. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
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
    v_error_count INT := 0; -- For rows marked as error in this step
    v_default_valid_after DATE; -- Renamed for clarity
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

    -- Calculate default_valid_after based on job default
    IF v_job.default_valid_from IS NOT NULL THEN
        v_default_valid_after := v_job.default_valid_from - INTERVAL '1 day';
    ELSE
        v_default_valid_after := NULL;
    END IF;

    -- Check if the job's default dates themselves form an invalid period or involve NULLs for NOT NULL columns
    IF v_job.default_valid_from IS NULL OR v_job.default_valid_to IS NULL OR v_default_valid_after >= v_job.default_valid_to THEN
        -- Mark all applicable rows in the batch as error
        v_sql := format($$
            UPDATE public.%I dt SET
                derived_valid_after = %L, -- Store potentially problematic default_valid_after
                derived_valid_from = %L,
                derived_valid_to = %L,
                last_completed_priority = %L, -- Advance to current step's priority on error
                error = COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('invalid_period_context', 
                    CASE 
                        WHEN %L::DATE IS NULL THEN 'Job default_valid_from is NULL, resulting in NULL derived_valid_after for a NOT NULL column.'
                        WHEN %L::DATE IS NULL THEN 'Job default_valid_to is NULL for a NOT NULL column.'
                        ELSE 'Job default dates create an invalid period (derived_valid_after >= derived_valid_to).'
                    END),
                state = 'error',
                action = 'skip'::public.import_row_action_type -- Error implies skip
            WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Only update rows not already skipped by a *prior* step.
        $$, v_data_table_name, 
             v_default_valid_after, v_job.default_valid_from, v_job.default_valid_to,
             v_step.priority, -- For last_completed_priority
             v_job.default_valid_from, v_job.default_valid_to, -- For CASE check
             p_batch_row_ids);
        RAISE DEBUG '[Job %] analyse_valid_time_from_context: Job default dates are invalid. Marking non-skipped rows as error and action=skip: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time_from_context: Marked % non-skipped rows as error due to invalid job default dates.', p_job_id, v_error_count;
    ELSE
        -- Job default dates are valid, proceed to update rows
        v_sql := format($$
            UPDATE public.%I dt SET
                derived_valid_after = %L, -- Use pre-calculated v_default_valid_after
                derived_valid_from = %L::DATE,
                derived_valid_to = %L::DATE,
                last_completed_priority = %L,
                error = CASE WHEN (dt.error - ARRAY['invalid_period_context']::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - ARRAY['invalid_period_context']::TEXT[]) END, -- Clear only our specific error key
                state = 'analysing' -- Action remains as determined by previous steps
            WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; 
        $$, v_data_table_name, v_default_valid_after, v_job.default_valid_from, v_job.default_valid_to, v_step.priority, p_batch_row_ids);
        RAISE DEBUG '[Job %] analyse_valid_time_from_context: Updating derived dates for non-skipped rows: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time_from_context: Marked % non-skipped rows as success for this target.', p_job_id, v_update_count;
    END IF;

    -- Update priority for already skipped rows (this part remains the same)
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT; -- This v_update_count is for skipped rows
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Advanced priority for % pre-skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Finished analysis for batch. Errors in this step: %', p_job_id, v_error_count;
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
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from_source', 'valid_to_source', 'invalid_period_source'];
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
        WITH casted_dates_cte AS ( -- Renamed CTE
            SELECT
                dt_sub.row_id,
                (import.safe_cast_to_date(dt_sub.valid_from)).p_value as casted_vf,
                (import.safe_cast_to_date(dt_sub.valid_from)).p_error_message as vf_error_msg,
                (import.safe_cast_to_date(dt_sub.valid_to)).p_value as casted_vt,
                (import.safe_cast_to_date(dt_sub.valid_to)).p_error_message as vt_error_msg,
                dt_sub.valid_from as original_vf, -- Keep original for error messages
                dt_sub.valid_to as original_vt   -- Keep original for error messages
            FROM public.%I dt_sub
            WHERE dt_sub.row_id = ANY(%L)
        )
        UPDATE public.%I dt SET
            derived_valid_from = cdc.casted_vf, -- Use cdc alias
            derived_valid_after = cdc.casted_vf - INTERVAL '1 day',
            derived_valid_to = cdc.casted_vt,
            state = CASE
                        WHEN cdc.original_vf IS NULL OR cdc.vf_error_msg IS NOT NULL OR 
                             cdc.original_vt IS NULL OR cdc.vt_error_msg IS NOT NULL OR 
                             (cdc.casted_vf IS NOT NULL AND cdc.casted_vt IS NOT NULL AND (cdc.casted_vf - INTERVAL '1 day' >= cdc.casted_vt))
                        THEN 'error'::public.import_data_state
                        ELSE -- No error in this step
                            CASE
                                WHEN dt.state = 'error'::public.import_data_state THEN 'error'::public.import_data_state -- Preserve previous error
                                ELSE 'analysing'::public.import_data_state -- OK to set to analysing
                            END
                    END,
            action = CASE
                        WHEN cdc.original_vf IS NULL OR cdc.vf_error_msg IS NOT NULL OR 
                             cdc.original_vt IS NULL OR cdc.vt_error_msg IS NOT NULL OR 
                             (cdc.casted_vf IS NOT NULL AND cdc.casted_vt IS NOT NULL AND (cdc.casted_vf - INTERVAL '1 day' >= cdc.casted_vt))
                        THEN 'skip'::public.import_row_action_type -- Error implies skip
                        ELSE dt.action -- Preserve action from previous steps if no new fatal error here
                     END,
            error = CASE
                        WHEN cdc.original_vf IS NULL THEN -- Mandatory value missing
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_from_source', 'Missing mandatory value')
                        WHEN cdc.vf_error_msg IS NOT NULL THEN -- Cast error for valid_from
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_from_source', cdc.vf_error_msg)
                        WHEN cdc.original_vt IS NULL THEN -- Mandatory value missing
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_to_source', 'Missing mandatory value')
                        WHEN cdc.vt_error_msg IS NOT NULL THEN -- Cast error for valid_to
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_to_source', cdc.vt_error_msg)
                        WHEN cdc.casted_vf IS NOT NULL AND cdc.casted_vt IS NOT NULL AND (cdc.casted_vf - INTERVAL '1 day' >= cdc.casted_vt) THEN -- Invalid period
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('invalid_period_source', 'Resulting valid_after (' || (cdc.casted_vf - INTERVAL '1 day')::TEXT || ') is not before valid_to (' || cdc.casted_vt::TEXT || ')')
                        ELSE -- No error from this step, clear specific keys
                            CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            last_completed_priority = %s -- Always v_step.priority
        FROM casted_dates_cte cdc -- Use cdc alias
        WHERE dt.row_id = cdc.row_id AND dt.action IS DISTINCT FROM 'skip'; -- Process if action was not already 'skip' from a prior step.
    $$,
        v_data_table_name, p_batch_row_ids,                     -- For CTE
        v_data_table_name,                                      -- For main UPDATE target
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,   -- For error CASE (clear)
        v_step.priority                                         -- For last_completed_priority (always this step's priority)
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
