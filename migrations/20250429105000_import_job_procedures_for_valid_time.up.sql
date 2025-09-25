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
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from_raw', 'valid_to_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'valid_time';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time step not found in snapshot', p_job_id;
    END IF;

    -- Create a temporary table to hold batch data. This ensures subsequent operations are on a small dataset.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    CREATE TEMP TABLE t_batch_data (
        row_id integer PRIMARY KEY,
        valid_from TEXT,
        valid_to TEXT
    ) ON COMMIT DROP;

    -- Populate the temp table using the performant unnest/JOIN strategy, which forces use of the PK B-tree index.
    EXECUTE format(
        'INSERT INTO t_batch_data (row_id, valid_from, valid_to) SELECT dt.row_id, dt.valid_from_raw, dt.valid_to_raw FROM public.%I dt JOIN unnest($1) AS r(range) ON dt.row_id >= lower(r.range) AND dt.row_id < upper(r.range)',
        v_data_table_name
    ) USING p_batch_row_id_ranges;

    ANALYZE t_batch_data; -- Provide stats for the planner.

    -- Single-pass batch update for casting, state, error, and priority
    v_sql := format($SQL$
        WITH
        -- Step 1: Get the raw text dates for the current batch of rows from the temp table.
        batch_data_cte AS (
            SELECT row_id, valid_from, valid_to FROM t_batch_data
        ),
        -- Step 2: Find all unique non-empty date strings within the batch.
        distinct_dates_cte AS (
            SELECT valid_from AS date_string FROM batch_data_cte WHERE NULLIF(valid_from, '') IS NOT NULL
            UNION
            SELECT valid_to AS date_string FROM batch_data_cte WHERE NULLIF(valid_to, '') IS NOT NULL
        ),
        -- Step 3: Call the casting function ONLY for the unique date strings.
        casted_distinct_dates_cte AS MATERIALIZED (
            SELECT
                dd.date_string,
                sc.p_value,
                sc.p_error_message
            FROM distinct_dates_cte dd
            LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
        ),
        -- Step 4: Re-assemble the casted values for each row by joining back to the batch data.
        final_cast_cte AS (
            SELECT
                bd.row_id,
                vf.p_value AS casted_vf,
                vf.p_error_message AS vf_error_msg,
                vt.p_value AS casted_vt,
                vt.p_error_message AS vt_error_msg,
                (CASE WHEN vt.p_value = 'infinity'::date THEN 'infinity'::date ELSE vt.p_value + INTERVAL '1 day' END) AS casted_vu,
                bd.valid_from AS original_vf,
                bd.valid_to AS original_vt
            FROM batch_data_cte bd
            LEFT JOIN casted_distinct_dates_cte vf ON bd.valid_from = vf.date_string
            LEFT JOIN casted_distinct_dates_cte vt ON bd.valid_to = vt.date_string
        )
        UPDATE public.%1$I dt SET
            valid_from = fcc.casted_vf,
            valid_to = fcc.casted_vt,
            valid_until = fcc.casted_vu,
            state = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'error'::public.import_data_state
                        ELSE
                            CASE
                                WHEN dt.state = 'error'::public.import_data_state THEN 'error'::public.import_data_state
                                ELSE 'analysing'::public.import_data_state
                            END
                    END,
            action = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL THEN
                            dt.errors || jsonb_build_object('valid_from_raw', 'Missing mandatory value')
                        WHEN fcc.vf_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('valid_from_raw', fcc.vf_error_msg)
                        WHEN NULLIF(fcc.original_vt, '') IS NULL THEN
                            dt.errors || jsonb_build_object('valid_to_raw', 'Missing mandatory value')
                        WHEN fcc.vt_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('valid_to_raw', fcc.vt_error_msg)
                        WHEN fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND (fcc.casted_vf >= fcc.casted_vu) THEN
                            dt.errors || jsonb_build_object(
                                'valid_from_raw', 'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')',
                                'valid_to_raw',   'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')'
                            )
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            last_completed_priority = %3$L
        FROM final_cast_cte fcc
        WHERE dt.row_id = fcc.row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_step.priority                -- %3$L
    );
    RAISE DEBUG '[Job %] analyse_valid_time: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Estimate error count
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt JOIN unnest($1) AS r(range) ON dt.row_id >= lower(r.range) AND dt.row_id < upper(r.range) WHERE dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
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

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, 'analyse_valid_time');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_valid_time: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_valid_time$;

-- Note: No process_valid_time_from_source procedure is needed.
-- The typed_valid_from/to columns are used by the main unit processing procedures (legal_unit, establishment).

COMMIT;
