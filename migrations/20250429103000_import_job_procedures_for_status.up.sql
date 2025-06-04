-- Implements the analyse procedure for the status import step.

BEGIN;

-- Procedure to analyse status_code and populate status_id (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_status(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_status$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_default_status_id INT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['status_code']; -- Changed error key
BEGIN
    RAISE DEBUG '[Job %] analyse_status (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM public.import_step WHERE code = 'status';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] status step not found', p_job_id;
    END IF;

    -- Get default status_id
    SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND active = true LIMIT 1;
    RAISE DEBUG '[Job %] analyse_status: Default status_id found: %', p_job_id, v_default_status_id;

    v_sql := format($$
        WITH status_lookup AS (
            SELECT
                dt_sub.row_id as data_row_id,
                s.id as resolved_status_id_by_code
            FROM public.%I dt_sub
            LEFT JOIN public.status s ON NULLIF(dt_sub.status_code, '') IS NOT NULL AND s.code = dt_sub.status_code AND s.active = true
            WHERE dt_sub.row_id = ANY(%L) AND dt_sub.action IS DISTINCT FROM 'skip' -- Process rows not yet skipped
        )
        UPDATE public.%I dt SET
            status_id = CASE
                            WHEN NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NOT NULL THEN sl.resolved_status_id_by_code
                            WHEN NULLIF(dt.status_code, '') IS NULL OR NULLIF(dt.status_code, '') = '' THEN %L::INTEGER -- Use default if no code provided
                            WHEN NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL THEN %L::INTEGER -- Use default if code provided but not found/inactive
                            ELSE dt.status_id -- Keep existing if no condition met (should not happen if logic is complete)
                        END,
            action = CASE
                        WHEN (NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %L::INTEGER IS NULL) OR 
                             ((NULLIF(dt.status_code, '') IS NULL OR NULLIF(dt.status_code, '') = '') AND %L::INTEGER IS NULL)      
                        THEN 'skip'::public.import_row_action_type
                        ELSE dt.action 
                     END,
            state = CASE
                        WHEN (NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %L::INTEGER IS NULL) OR
                             ((NULLIF(dt.status_code, '') IS NULL OR NULLIF(dt.status_code, '') = '') AND %L::INTEGER IS NULL)
                        THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            error = CASE
                        WHEN NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %L::INTEGER IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('status_code', 'Provided status_code ''' || dt.status_code || ''' not found/active and no default available')
                        WHEN (NULLIF(dt.status_code, '') IS NULL OR NULLIF(dt.status_code, '') = '') AND %L::INTEGER IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('status_code', 'Status code not provided and no active default status found')
                        ELSE
                            CASE WHEN (dt.error - %L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %L::TEXT[]) END
                    END,
            invalid_codes =
                CASE
                    -- Soft error: Invalid code provided, but default is available and used.
                    WHEN NULLIF(dt.status_code, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %L::INTEGER IS NOT NULL THEN
                        COALESCE(dt.invalid_codes, '{}'::jsonb) || jsonb_build_object('status_code', dt.status_code)
                    -- Default case: clear 'status_code' from invalid_codes if it exists (e.g. if code is valid or hard error occurs for status_code).
                    ELSE
                        CASE WHEN (COALESCE(dt.invalid_codes, '{}'::jsonb) - 'status_code') = '{}'::jsonb THEN NULL ELSE (COALESCE(dt.invalid_codes, '{}'::jsonb) - 'status_code') END
                END,
            last_completed_priority = %L::INTEGER -- Always v_step.priority
        FROM status_lookup sl
        WHERE dt.row_id = sl.data_row_id AND dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip';
    $$,
        v_data_table_name, p_batch_row_ids,                     -- For status_lookup CTE
        v_data_table_name,                                      -- For main UPDATE target
        v_default_status_id, v_default_status_id,               -- For status_id CASE (default)
        v_default_status_id, v_default_status_id,               -- For action CASE (error conditions)
        v_default_status_id, v_default_status_id,               -- For state CASE (error conditions)
        v_default_status_id,                                    -- For error CASE (code not found & no default)
        v_default_status_id,                                    -- For error CASE (no code & no default)
        v_error_keys_to_clear_arr, v_error_keys_to_clear_arr,   -- For error CASE (clear)
        v_default_status_id,                                    -- For invalid_codes CASE (soft error condition)
        v_step.priority,                                        -- For last_completed_priority (always this step's priority)
        p_batch_row_ids                                         -- For final WHERE clause
    );

    RAISE DEBUG '[Job %] analyse_status: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_status: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        EXECUTE format('
            UPDATE public.%I dt SET
                last_completed_priority = %L
            WHERE dt.row_id = ANY(%L) AND dt.action = ''skip''; -- Only update LCP for rows already skipped
        ', v_data_table_name, v_step.priority, p_batch_row_ids);
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_status: Updated last_completed_priority for % pre-skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count;

        EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE row_id = ANY(%L) AND state = ''error'' AND (error ?| %L::text[])',
                       v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr)
        INTO v_error_count;
        RAISE DEBUG '[Job %] analyse_status: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_status: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_status_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_status: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_status (Batch): Finished analysis for batch. Errors newly marked: %', p_job_id, v_error_count;
END;
$analyse_status$;

COMMIT;
