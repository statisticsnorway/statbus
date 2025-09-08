-- Migration: import_job_procedures_for_activity
-- Implements the analyse and operation procedures for the PrimaryActivity
-- and SecondaryActivity import targets using generic activity handlers.

BEGIN;

-- Procedure to analyse activity data (handles both primary and secondary) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_activity(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_activity$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0; -- Added from location
    v_sql TEXT;
    -- v_error_json_primary TEXT; -- Replaced by v_error_json_expr_sql
    -- v_error_json_secondary TEXT; -- Replaced by v_error_json_expr_sql
    v_error_keys_to_clear_arr TEXT[];
    v_job_mode public.import_mode;
    v_source_code_col_name TEXT; -- e.g., primary_activity_category_code
    v_resolved_id_col_name_in_lookup_cte TEXT; -- e.g., resolved_primary_activity_category_id
    v_json_key TEXT; -- e.g., primary_activity_category_code (for JSON keys)
    v_lookup_failed_condition_sql TEXT;
    v_error_json_expr_sql TEXT;
    v_invalid_code_json_expr_sql TEXT;
    v_parent_unit_missing_error_key TEXT;
    v_parent_unit_missing_error_message TEXT;
    v_prelim_update_count INT := 0;
    v_parent_id_check_sql TEXT; -- For dynamically building the parent ID check condition
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch) for step_code %: Starting analysis for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Get the specific step details using p_step_code from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_activity: Step with code % not found in snapshot. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Determine column names and JSON key based on the step being processed
    IF p_step_code = 'primary_activity' THEN
        v_source_code_col_name := 'primary_activity_category_code';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_primary_activity_category_id';
        v_json_key := 'primary_activity_category_code';
    ELSIF p_step_code = 'secondary_activity' THEN
        v_source_code_col_name := 'secondary_activity_category_code';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_secondary_activity_category_id';
        v_json_key := 'secondary_activity_category_code';
    ELSE
        RAISE EXCEPTION '[Job %] analyse_activity: Invalid p_step_code provided: %. Expected ''primary_activity'' or ''secondary_activity''.', p_job_id, p_step_code;
    END IF;
    v_error_keys_to_clear_arr := ARRAY[v_json_key];

    -- SQL condition string for when the lookup for the current activity type fails
    v_lookup_failed_condition_sql := format('dt.%1$I IS NOT NULL AND l.%2$I IS NULL', v_source_code_col_name /* %1$I */, v_resolved_id_col_name_in_lookup_cte /* %2$I */);

    -- SQL expression string for constructing the error JSON object for the current activity type
    v_error_json_expr_sql := format('jsonb_build_object(%1$L, ''Not found'')', v_json_key /* %1$L */);

    -- SQL expression string for constructing the invalid_codes JSON object for the current activity type
    v_invalid_code_json_expr_sql := format('jsonb_build_object(%1$L, dt.%2$I)', v_json_key /* %1$L */, v_source_code_col_name /* %2$I */);

    -- The preliminary parent ID check has been removed from analyse_activity.
    -- This check will now be handled in process_activity, as parent unit IDs (legal_unit_id, establishment_id)
    -- are populated by their respective process_ steps, which run after analysis steps.

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id AS data_row_id,
                pac.id as resolved_primary_activity_category_id,
                sac.id as resolved_secondary_activity_category_id
            FROM public.%1$I dt_sub -- Target data table
            LEFT JOIN public.activity_category pac ON dt_sub.primary_activity_category_code IS NOT NULL AND pac.code = dt_sub.primary_activity_category_code
            LEFT JOIN public.activity_category sac ON dt_sub.secondary_activity_category_code IS NOT NULL AND sac.code = dt_sub.secondary_activity_category_code
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action IS DISTINCT FROM 'skip' -- Exclude skipped rows from main processing
        )
        UPDATE public.%1$I dt SET -- Target data table
            primary_activity_category_id = CASE
                                               WHEN %2$L = 'primary_activity' THEN l.resolved_primary_activity_category_id
                                               ELSE dt.primary_activity_category_id -- Keep existing if not this step's target
                                           END,
            secondary_activity_category_id = CASE
                                                 WHEN %2$L = 'secondary_activity' THEN l.resolved_secondary_activity_category_id
                                                 ELSE dt.secondary_activity_category_id -- Keep existing if not this step's target
                                             END,
            state = 'analysing'::public.import_data_state, -- Activity lookup issues are non-fatal, state remains analysing
            errors = CASE WHEN (dt.errors - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.errors - %3$L::TEXT[]) END, -- Always clear this step's error key
            invalid_codes = CASE
                                WHEN (%4$s) THEN -- Lookup failed for the current activity type
                                    COALESCE(dt.invalid_codes, '{}'::jsonb) || jsonb_strip_nulls(%5$s) -- Add specific invalid code with original value
                                ELSE -- Success for this activity type: clear this step's invalid_code key
                                    CASE WHEN (dt.invalid_codes - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.invalid_codes - %3$L::TEXT[]) END
                            END,
            last_completed_priority = %6$L::INTEGER -- Always advance priority for this step
        FROM lookups l
        WHERE dt.row_id = l.data_row_id; -- Join is sufficient, lookups CTE is already filtered
    $$,
        v_data_table_name /* %1$I */,                           -- Used for both CTE and UPDATE target
        p_step_code /* %2$L */,                                 -- Reused in both primary/secondary CASEs
        v_error_keys_to_clear_arr /* %3$L */,                   -- Keys to clear (reused in error and invalid_codes)
        v_lookup_failed_condition_sql /* %4$s */,               -- Condition for lookup failure
        v_invalid_code_json_expr_sql /* %5$s */,                -- JSON for invalid code
        v_step.priority /* %6$L */                              -- Always advance to current step's priority
    );

    RAISE DEBUG '[Job %] analyse_activity: Single-pass batch update for non-skipped rows for step % (activity issues now non-fatal for all modes): %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_activity: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_activity: Updated last_completed_priority for % skipped rows for step %.', p_job_id, v_skipped_update_count, p_step_code;
        
        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
        RAISE DEBUG '[Job %] analyse_activity: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_activity: Error during single-pass batch update for step %: %', p_job_id, p_step_code, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_activity_batch_error', SQLERRM, 'step_code', p_step_code),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_activity: Marked job as failed due to error in step %: %', p_job_id, p_step_code, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$analyse_activity$;


-- Procedure to operate (insert/update/upsert) activity data (handles both primary and secondary) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_activity(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_activity$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_source_view_name TEXT;
    v_relevant_rows_count INT;
BEGIN
    RAISE DEBUG '[Job %] process_activity (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Get step details
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] process_activity: Step with code % not found in snapshot.', p_job_id, p_step_code; END IF;

    v_job_mode := v_definition.mode;

    -- Select the correct parent unit ID column based on job mode, or NULL if not applicable.
    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_activity: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Create an updatable view over the relevant data for this step
    v_source_view_name := 'temp_act_source_view_' || p_step_code;
    IF p_step_code = 'primary_activity' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.primary_activity_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'primary'::public.activity_type AS type,
                dt.primary_activity_category_id AS category_id,
                dt.derived_valid_from AS valid_from,
                dt.derived_valid_to AS valid_to,
                dt.derived_valid_until AS valid_until,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_statuses
            FROM public.%4$I dt
            WHERE dt.row_id = ANY(%5$L)
              AND dt.action = 'use'
              AND dt.state != 'error'
              AND dt.primary_activity_category_id IS NOT NULL;
        $$, v_source_view_name, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name, p_batch_row_ids);

    ELSIF p_step_code = 'secondary_activity' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.secondary_activity_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'secondary'::public.activity_type AS type,
                dt.secondary_activity_category_id AS category_id,
                dt.derived_valid_from AS valid_from,
                dt.derived_valid_to AS valid_to,
                dt.derived_valid_until AS valid_until,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_statuses
            FROM public.%4$I dt
            WHERE dt.row_id = ANY(%5$L)
              AND dt.action = 'use'
              AND dt.state != 'error'
              AND dt.secondary_activity_category_id IS NOT NULL;
        $$, v_source_view_name, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name, p_batch_row_ids);
    ELSE
        RAISE EXCEPTION '[Job %] process_activity: Invalid step_code %.', p_job_id, p_step_code;
    END IF;

    EXECUTE v_sql;

    EXECUTE format('SELECT count(*) FROM %I', v_source_view_name) INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_activity: No usable activity data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_activity: Calling sql_saga.temporal_merge for % rows (step: %).', p_job_id, v_relevant_rows_count, p_step_code;

    BEGIN
        CALL sql_saga.temporal_merge(
            p_target_table => 'public.activity'::regclass,
            p_source_table => v_source_view_name::regclass,
            p_identity_columns => ARRAY['id'],
            p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
            p_mode => 'MERGE_ENTITY_REPLACE',
            p_identity_correlation_column => 'founding_row_id',
            p_update_source_with_identity => true,
            p_update_source_with_feedback => true,
            p_feedback_status_column => 'merge_statuses',
            p_feedback_status_key => p_step_code,
            p_feedback_error_column => 'errors',
            p_feedback_error_key => p_step_code,
            p_source_row_id_column => 'row_id'
        );

        EXECUTE format($$ SELECT count(*) FROM public.%1$I WHERE row_id = ANY($1) AND errors->%2$L IS NOT NULL $$, v_data_table_name, p_step_code)
            INTO v_error_count USING p_batch_row_ids;

        EXECUTE format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors IS NULL THEN 'processing' ELSE 'error' END
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$, v_data_table_name, v_source_view_name);
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_activity: Merge finished for step %. Success: %, Errors: %', p_job_id, p_step_code, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_activity: Error during temporal_merge for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || jsonb_build_object('batch_error_process_activity', %2$L) WHERE row_id = ANY($1)$$,
                        v_data_table_name, error_message);
        EXECUTE v_sql USING p_batch_row_ids;
        RAISE; -- Re-throw
    END;

    RAISE DEBUG '[Job %] process_activity (Batch): Finished for step %. Total Processed: %, Errors: %',
        p_job_id, p_step_code, v_update_count + v_error_count, v_error_count;
END;
$process_activity$;


COMMIT;
