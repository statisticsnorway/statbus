-- Implements the analyse procedure for the status import step.

BEGIN;

-- Procedure to analyse status_code and populate status_id (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_status(p_job_id INT, p_batch_seq INTEGER, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_status$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_default_status_id INT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['status_code_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_status (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'status';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] status step not found in snapshot', p_job_id;
    END IF;

    -- Get default status_id
    SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    RAISE DEBUG '[Job %] analyse_status: Default status_id found: %', p_job_id, v_default_status_id;

    v_sql := format($$
        WITH
        batch_data AS (
            SELECT dt.row_id, dt.status_code_raw AS status_code
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1
              AND dt.action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT status_code AS code
            FROM batch_data
            WHERE NULLIF(status_code, '') IS NOT NULL
            GROUP BY 1
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                s.id as resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.status s ON s.code = dc.code AND s.active = true
        ),
        status_lookup AS (
            SELECT
                bd.row_id as data_row_id,
                rc.resolved_id as resolved_status_id_by_code
            FROM batch_data bd
            LEFT JOIN resolved_codes rc ON bd.status_code = rc.code
        )
        UPDATE public.%1$I dt SET
            status_id = CASE
                            WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NOT NULL THEN sl.resolved_status_id_by_code
                            WHEN NULLIF(dt.status_code_raw, '') IS NULL THEN %2$L::INTEGER -- Use default if no code provided
                            WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL THEN %2$L::INTEGER -- Use default if code provided but not found/inactive
                            ELSE dt.status_id -- Keep existing if no condition met (should not happen if logic is complete)
                        END,
            action = CASE
                        WHEN (NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL) OR 
                             (NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL)      
                        THEN 'skip'::public.import_row_action_type
                        ELSE dt.action 
                     END,
            state = CASE
                        WHEN (NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL) OR
                             (NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL)
                        THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = CASE
                        WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Provided status_code ''' || dt.status_code_raw || ''' not found/active and no default available')
                        WHEN NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code not provided and no active default status found')
                        ELSE
                            dt.errors - %3$L::TEXT[]
                    END,
            invalid_codes =
                CASE
                    -- Soft error: Invalid code provided, but default is available and used.
                    WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NOT NULL THEN
                        dt.invalid_codes || jsonb_build_object('status_code_raw', dt.status_code_raw)
                    -- Default case: clear 'status_code_raw' from invalid_codes if it exists (e.g. if code is valid or hard error occurs for status_code).
                    ELSE
                        dt.invalid_codes - 'status_code_raw'
                END,
            last_completed_priority = %4$L::INTEGER -- Always v_step.priority
        FROM status_lookup sl
        WHERE dt.row_id = sl.data_row_id;
    $$,
        v_data_table_name /* %1$I */,            -- Table used in both CTE and UPDATE
        v_default_status_id /* %2$L */,          -- Default status_id (reused in many places)
        v_error_keys_to_clear_arr /* %3$L */,    -- Keys to clear from error JSON
        v_step.priority /* %4$L */               -- last_completed_priority
    );

    RAISE DEBUG '[Job %] analyse_status: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_status: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_status: Counting errors in batch with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_status: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_status: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_status_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_status: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_status: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_status: Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_status');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_status: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_status (Batch): Finished analysis for batch. Errors newly marked: %', p_job_id, v_error_count;
END;
$analyse_status$;

COMMIT;
