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

-- The procedure analyse_valid_time_from_context has been removed.
-- Its logic is now handled declaratively by using mappings with `source_expression = 'default'`
-- which populates the `source_input` `valid_from`/`valid_to` columns in the `_data` table
-- during the prepare step. The existing `analyse_valid_time_from_source` procedure
-- can then process these columns uniformly for all `valid_time_from` modes.


-- Procedure to analyse the validity period for a job.
-- This single procedure handles all `valid_time_from` modes by operating on the
-- `valid_from` and `valid_to` source_input columns in the `_data` table, which are
-- populated either from the source file or from job defaults during the prepare step.
CREATE OR REPLACE PROCEDURE import.analyse_valid_time(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_valid_time$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from', 'valid_to']; -- Adjusted to match source_input column names
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'valid_time';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time target not found in snapshot', p_job_id;
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
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_from', 'Missing mandatory value')
                        WHEN cdc.vf_error_msg IS NOT NULL THEN -- Cast error for valid_from
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_from', cdc.vf_error_msg)
                        WHEN cdc.original_vt IS NULL THEN -- Mandatory value missing
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_to', 'Missing mandatory value')
                        WHEN cdc.vt_error_msg IS NOT NULL THEN -- Cast error for valid_to
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('valid_to', cdc.vt_error_msg)
                        WHEN cdc.casted_vf IS NOT NULL AND cdc.casted_vt IS NOT NULL AND (cdc.casted_vf - INTERVAL '1 day' >= cdc.casted_vt) THEN -- Invalid period
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object(
                                'valid_from', 'Resulting period is invalid: derived_valid_after (' || (cdc.casted_vf - INTERVAL '1 day')::TEXT || ') is not before valid_to (' || cdc.casted_vt::TEXT || ')',
                                'valid_to',   'Resulting period is invalid: derived_valid_after (' || (cdc.casted_vf - INTERVAL '1 day')::TEXT || ') is not before valid_to (' || cdc.casted_vt::TEXT || ')'
                            )
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
    RAISE DEBUG '[Job %] analyse_valid_time: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip'';
        ', v_data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        -- Estimate error count
        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_valid_time: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_valid_time: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_valid_time_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_valid_time: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_valid_time$;

-- Note: No process_valid_time_from_source procedure is needed.
-- The typed_valid_from/to columns are used by the main unit processing procedures (legal_unit, establishment).

COMMIT;
