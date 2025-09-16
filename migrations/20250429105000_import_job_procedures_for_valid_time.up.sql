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
CREATE OR REPLACE PROCEDURE import.analyse_valid_time(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_valid_time$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from_raw', 'valid_to_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'valid_time';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time target not found in snapshot', p_job_id;
    END IF;

    -- Single-pass batch update for casting, state, error, and priority
    v_sql := format($SQL$
        WITH
        -- Step 1: Get the raw text dates for the current batch of rows.
        batch_data_cte AS (
            SELECT row_id, valid_from_raw AS valid_from, valid_to_raw AS valid_to FROM public.%1$I WHERE row_id <@ $1
        ),
        -- Step 2: Find all unique non-empty date strings within the batch.
        distinct_dates_cte AS (
            SELECT valid_from AS date_string FROM batch_data_cte WHERE NULLIF(valid_from, '') IS NOT NULL
            UNION
            SELECT valid_to AS date_string FROM batch_data_cte WHERE NULLIF(valid_to, '') IS NOT NULL
        ),
        -- Step 3: Call the casting function ONLY for the unique date strings.
        casted_distinct_dates_cte AS (
            SELECT
                dd.date_string,
                sc.p_value,
                sc.p_error_message
            FROM distinct_dates_cte dd
            LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
        ),
        -- Step 4: Re-assemble the casted values for each row by joining back to the batch data.
        -- This serves as the main source for the final UPDATE statement.
        final_cast_cte AS (
            SELECT
                bd.row_id,
                -- Casted values for 'valid_from'
                vf.p_value AS casted_vf,
                vf.p_error_message AS vf_error_msg,
                -- Casted values for 'valid_to'
                vt.p_value AS casted_vt,
                vt.p_error_message AS vt_error_msg,
                -- The 'valid_until' is derived from the casted 'valid_to'
                (CASE WHEN vt.p_value = 'infinity'::date THEN 'infinity'::date ELSE vt.p_value + INTERVAL '1 day' END) AS casted_vu,
                -- Keep original string values for use in error messages
                bd.valid_from AS original_vf,
                bd.valid_to AS original_vt
            FROM batch_data_cte bd
            LEFT JOIN casted_distinct_dates_cte vf ON bd.valid_from = vf.date_string
            LEFT JOIN casted_distinct_dates_cte vt ON bd.valid_to = vt.date_string
        )
        UPDATE public.%2$I dt SET
            valid_from = fcc.casted_vf,
            valid_to = fcc.casted_vt,
            valid_until = fcc.casted_vu,
            state = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'error'::public.import_data_state
                        ELSE -- No error in this step
                            CASE
                                WHEN dt.state = 'error'::public.import_data_state THEN 'error'::public.import_data_state -- Preserve previous error
                                ELSE 'analysing'::public.import_data_state -- OK to set to analysing
                            END
                    END,
            action = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'skip'::public.import_row_action_type -- Error implies skip
                        ELSE dt.action -- Preserve action from previous steps if no new fatal error here
                     END,
            errors = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL THEN -- Mandatory value missing
                            dt.errors || jsonb_build_object('valid_from_raw', 'Missing mandatory value')
                        WHEN fcc.vf_error_msg IS NOT NULL THEN -- Cast error for valid_from
                            dt.errors || jsonb_build_object('valid_from_raw', fcc.vf_error_msg)
                        WHEN NULLIF(fcc.original_vt, '') IS NULL THEN -- Mandatory value missing
                            dt.errors || jsonb_build_object('valid_to_raw', 'Missing mandatory value')
                        WHEN fcc.vt_error_msg IS NOT NULL THEN -- Cast error for valid_to
                            dt.errors || jsonb_build_object('valid_to_raw', fcc.vt_error_msg)
                        WHEN fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND (fcc.casted_vf >= fcc.casted_vu) THEN -- Invalid period
                            dt.errors || jsonb_build_object(
                                'valid_from_raw', 'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')',
                                'valid_to_raw',   'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')'
                            )
                        ELSE -- No error from this step, clear specific keys
                            dt.errors - %3$L::TEXT[]
                    END,
            last_completed_priority = %4$L -- Always v_step.priority
        FROM final_cast_cte fcc
        WHERE dt.row_id = fcc.row_id AND dt.action IS DISTINCT FROM 'skip'; -- Process if action was not already 'skip' from a prior step.
    $SQL$,
        v_data_table_name /* %1$I */,                           -- %1$I (CTE source table)
        v_data_table_name /* %2$I */,                           -- %2$I (main UPDATE target)
        v_error_keys_to_clear_arr /* %3$L */,                    -- For error CASE (clear)
        v_step.priority /* %4$L */                              -- For last_completed_priority (always this step's priority)
    );
    RAISE DEBUG '[Job %] analyse_valid_time: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id <@ $1 AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
        RAISE DEBUG '[Job %] analyse_valid_time: Updating priority for skipped rows with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        -- Estimate error count
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id <@ $1 AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_valid_time: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_row_id_ranges;
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

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, 'analyse_valid_time');

    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_valid_time$;

-- Note: No process_valid_time_from_source procedure is needed.
-- The typed_valid_from/to columns are used by the main unit processing procedures (legal_unit, establishment).

COMMIT;
