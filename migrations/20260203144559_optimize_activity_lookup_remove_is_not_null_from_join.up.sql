-- Migration 20260203144559: optimize_activity_lookup_remove_is_not_null_from_join
--
-- PERF: Remove IS NOT NULL from LEFT JOIN condition for activity category lookups
--
-- Problem: The original join condition includes IS NOT NULL which prevents PostgreSQL
-- from using a hash join, forcing it to use nested loop with O(n²) comparisons.
-- Example: 24,026 rows × 2,215 categories = 53,217,590 comparisons (53M row filter)
--
-- Solution: Remove IS NOT NULL from join - NULL codes won't match any category code
-- anyway (NULL = 'anything' evaluates to NULL/false), so the semantic is preserved.
--
-- Result: 121ms → 12ms (10x speedup per query), affects multiple queries per import

BEGIN;

CREATE OR REPLACE PROCEDURE import.analyse_activity(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_activity$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[];
    v_job_mode public.import_mode;
    v_source_code_col_name TEXT;
    v_resolved_id_col_name_in_lookup_cte TEXT;
    v_json_key TEXT;
    v_lookup_failed_condition_sql TEXT;
    v_error_json_expr_sql TEXT;
    v_invalid_code_json_expr_sql TEXT;
    v_parent_unit_missing_error_key TEXT;
    v_parent_unit_missing_error_message TEXT;
    v_prelim_update_count INT := 0;
    v_parent_id_check_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch) for step_code %: Starting analysis for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Get the specific step details using p_step_code from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_activity: Step with code % not found in snapshot. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Determine column names and JSON key based on the step being processed
    IF p_step_code = 'primary_activity' THEN
        v_source_code_col_name := 'primary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_primary_activity_category_id';
        v_json_key := 'primary_activity_category_code_raw';
    ELSIF p_step_code = 'secondary_activity' THEN
        v_source_code_col_name := 'secondary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_secondary_activity_category_id';
        v_json_key := 'secondary_activity_category_code_raw';
    ELSE
        RAISE EXCEPTION '[Job %] analyse_activity: Invalid p_step_code provided: %. Expected ''primary_activity'' or ''secondary_activity''.', p_job_id, p_step_code;
    END IF;
    v_error_keys_to_clear_arr := ARRAY[v_json_key];

    -- SQL condition string for when the lookup for the current activity type fails
    v_lookup_failed_condition_sql := format('dt.%1$I IS NOT NULL AND l.%2$I IS NULL', v_source_code_col_name, v_resolved_id_col_name_in_lookup_cte);

    -- SQL expression string for constructing the error JSON object for the current activity type
    v_error_json_expr_sql := format('jsonb_build_object(%1$L, ''Not found'')', v_json_key);

    -- SQL expression string for constructing the invalid_codes JSON object for the current activity type
    v_invalid_code_json_expr_sql := format('jsonb_build_object(%1$L, dt.%2$I)', v_json_key, v_source_code_col_name);

    -- PERF: Removed IS NOT NULL from join conditions to enable hash join optimization.
    -- NULL codes won't match any category code anyway (NULL = 'x' evaluates to NULL/false).
    -- This reduces query time from O(n²) nested loop to O(n) hash join.
    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id AS data_row_id,
                pac.id as resolved_primary_activity_category_id,
                sac.id as resolved_secondary_activity_category_id
            FROM public.%1$I dt_sub -- Target data table
            LEFT JOIN public.activity_category_available pac ON pac.code = dt_sub.primary_activity_category_code_raw
            LEFT JOIN public.activity_category_available sac ON sac.code = dt_sub.secondary_activity_category_code_raw
            WHERE dt_sub.batch_seq = $1
        )
        UPDATE public.%1$I dt SET -- Target data table
            primary_activity_category_id = CASE
                                               WHEN %2$L = 'primary_activity' THEN l.resolved_primary_activity_category_id
                                               ELSE dt.primary_activity_category_id
                                           END,
            secondary_activity_category_id = CASE
                                                 WHEN %2$L = 'secondary_activity' THEN l.resolved_secondary_activity_category_id
                                                 ELSE dt.secondary_activity_category_id
                                             END,
            state = 'analysing'::public.import_data_state,
            errors = dt.errors - %3$L::TEXT[],
            invalid_codes = CASE
                                WHEN (%4$s) THEN
                                    dt.invalid_codes || jsonb_strip_nulls(%5$s)
                                ELSE
                                    dt.invalid_codes - %3$L::TEXT[]
                            END,
            last_completed_priority = %6$L::INTEGER
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.action IS DISTINCT FROM 'skip';
    $$,
        v_data_table_name,
        p_step_code,
        v_error_keys_to_clear_arr,
        v_lookup_failed_condition_sql,
        v_invalid_code_json_expr_sql,
        v_step.priority
    );

    RAISE DEBUG '[Job %] analyse_activity: Single-pass batch update for non-skipped rows for step % (activity issues now non-fatal for all modes): %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_activity: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_activity: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_activity: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_activity: Error during single-pass batch update for step %: %', p_job_id, p_step_code, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_activity_batch_error', SQLERRM, 'step_code', p_step_code)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_activity: Marked job as failed due to error in step %: %', p_job_id, p_step_code, SQLERRM;
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_activity: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$analyse_activity$;

END;
