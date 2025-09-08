-- Migration: import_job_procedures_for_stats
-- Implements the analyse and operation procedures for the statistical_variables import target.

BEGIN;

-- Helper function for safe integer casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_integer(
    IN p_text_value TEXT,
    OUT p_value INTEGER,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_value::INTEGER;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid integer format: ''' || p_text_value || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_value || ''' to integer. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;

-- Helper function for safe boolean casting
CREATE OR REPLACE FUNCTION import.safe_cast_to_boolean(
    IN p_text_value TEXT,
    OUT p_value BOOLEAN,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_value::BOOLEAN;
    EXCEPTION
        WHEN invalid_text_representation THEN -- Common for boolean cast errors
            p_error_message := 'Invalid boolean format: ''' || p_text_value || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_value || ''' to boolean. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;

-- Procedure to analyse statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_statistical_variables$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_conditions_sql TEXT := '';
    v_error_json_sql TEXT := '';
    v_error_keys_to_clear_list TEXT[];
    v_add_separator BOOLEAN := FALSE;
BEGIN
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; 
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; 

    IF v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found in snapshot', p_job_id;
    END IF;

    -- No longer filter v_stat_data_cols by step_id here.
    -- The loop will iterate over all source_input columns and join to stat_definition_active.
    IF v_stat_data_cols IS NULL OR jsonb_array_length(v_stat_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_statistical_variables: No data columns found in snapshot. Skipping analysis.', p_job_id;
         EXECUTE format($$UPDATE public.%1$I SET last_completed_priority = %2$L WHERE row_id = ANY($1)$$,
                        v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
         RETURN;
    END IF;

    v_add_separator := FALSE;
    FOR v_col_rec IN
        SELECT
            idc.value->>'column_name' as col_name, -- idc for import_data_column
            sda.type
        FROM jsonb_array_elements(v_stat_data_cols) idc -- Iterate over all data columns from snapshot
        JOIN public.stat_definition_active sda ON sda.code = (idc.value->>'column_name') -- Join to find actual stats
        WHERE idc.value->>'purpose' = 'source_input' -- Consider only source_input columns
    LOOP
        IF v_add_separator THEN
            v_error_conditions_sql := v_error_conditions_sql || ' OR ';
            v_error_json_sql := v_error_json_sql || ' || ';
        END IF;
        
        v_error_conditions_sql := v_error_conditions_sql || format(
            '(dt.%1$I IS NOT NULL AND (import.safe_cast_to_%2$s(dt.%1$I)).p_error_message IS NOT NULL)', -- Check p_error_message
            v_col_rec.col_name, /* %1$I */
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END /* %2$s */
        );
        
        v_error_json_sql := v_error_json_sql || format(
            'jsonb_build_object(%1$L, CASE WHEN dt.%2$I IS NOT NULL THEN (import.safe_cast_to_%3$s(dt.%2$I)).p_error_message ELSE NULL END)', -- Use p_error_message
            v_col_rec.col_name, /* %1$L */
            v_col_rec.col_name, /* %2$I */
            CASE v_col_rec.type WHEN 'int' THEN 'integer' WHEN 'float' THEN 'numeric' WHEN 'bool' THEN 'boolean' ELSE 'text' END /* %3$s */
        );
        -- Removed assignment to v_invalid_codes_json_sql as it's not declared and errors are fatal for this step.
        v_error_keys_to_clear_list := array_append(v_error_keys_to_clear_list, v_col_rec.col_name);
        v_add_separator := TRUE;
    END LOOP;

    IF v_error_conditions_sql = '' THEN -- Should not happen if v_stat_data_cols is not empty
        v_error_conditions_sql := 'FALSE';
        v_error_json_sql := '''{}''::jsonb';
    END IF;

    v_sql := format($$
        UPDATE public.%1$I dt SET
            -- Determine state first
            state = CASE
                        WHEN %2$s THEN 'error'::public.import_data_state -- Error condition for this step
                        ELSE 'analysing'::public.import_data_state -- No error from this step
                    END,
            -- Then determine action based on the new state or existing action
            action = CASE
                        WHEN %2$s THEN 'skip'::public.import_row_action_type -- If this step causes an error, action becomes 'skip'
                        ELSE dt.action -- Otherwise, preserve existing action
                     END,
            errors = CASE
                        WHEN %2$s THEN COALESCE(dt.errors, '{}'::jsonb) || jsonb_strip_nulls(%3$s) -- Error condition for this step
                        ELSE CASE WHEN (dt.errors - %4$L) = '{}'::jsonb THEN NULL ELSE (dt.errors - %4$L) END -- Clear errors specific to this step if no new error
                    END,
            last_completed_priority = %5$L -- Always v_step.priority
        WHERE dt.row_id = ANY($1) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$,
        v_data_table_name /* %1$I */,
        v_error_conditions_sql /* %2$s */, -- Reused for state/action/error conditions
        v_error_json_sql /* %3$s */,       -- Error JSON to append
        v_error_keys_to_clear_list /* %4$L */, -- Keys to clear from error JSON
        v_step.priority /* %5$L */            -- last_completed_priority (always this step's priority)
    );

    RAISE DEBUG '[Job %] analyse_statistical_variables: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;

        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_list /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_statistical_variables: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_statistical_variables_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_statistical_variables: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_list, 'analyse_statistical_variables');

    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$analyse_statistical_variables$;



-- Procedure to operate (insert/update/upsert) statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_statistical_variables$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_stat_def RECORD;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_source_view_name TEXT;
    v_relevant_rows_count INT;
    v_id_select_expr TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;
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
    ELSIF v_job_mode IS NULL THEN -- This is for stats_update jobs
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_statistical_variables: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Find step and data column details from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list';

    -- Loop over each statistical variable defined for this import and process it.
    FOR v_stat_def IN
        SELECT
            sda.id as stat_definition_id,
            sda.code as stat_code,
            sda.type as stat_type,
            idc.value->>'column_name' as source_col_name,
            pk_idc.value->>'column_name' as pk_col_name
        FROM jsonb_array_elements(v_stat_data_cols) idc
        JOIN public.stat_definition_active sda ON sda.code = (idc.value->>'column_name')
        LEFT JOIN jsonb_array_elements(v_stat_data_cols) pk_idc
            ON pk_idc.value->>'purpose' = 'pk_id'
           AND pk_idc.value->>'column_name' = 'stat_for_unit_' || sda.code
        WHERE idc.value->>'purpose' = 'source_input'
    LOOP
        -- Create a dedicated, updatable temp view for this specific statistical variable
        v_source_view_name := 'temp_stat_source_view_' || v_stat_def.stat_code;

        v_id_select_expr := CASE
            WHEN v_stat_def.pk_col_name IS NOT NULL THEN format('dt.%I', v_stat_def.pk_col_name)
            ELSE 'NULL::INTEGER'
        END;

        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                %2$s as id,
                %3$s AS legal_unit_id,
                %4$s AS establishment_id,
                %5$L::INTEGER as stat_definition_id,
                CASE %6$L
                    WHEN 'string' THEN dt.%7$I
                    ELSE NULL
                END AS value_string,
                CASE %6$L
                    WHEN 'int' THEN (import.safe_cast_to_integer(dt.%7$I)).p_value
                    ELSE NULL
                END AS value_int,
                CASE %6$L
                    WHEN 'float' THEN (import.safe_cast_to_numeric(dt.%7$I)).p_value
                    ELSE NULL
                END AS value_float,
                CASE %6$L
                    WHEN 'bool' THEN (import.safe_cast_to_boolean(dt.%7$I)).p_value
                    ELSE NULL
                END AS value_bool,
                dt.derived_valid_from AS valid_from,
                dt.derived_valid_to AS valid_to,
                dt.derived_valid_until AS valid_until,
                dt.data_source_id,
                dt.edit_by_user_id,
                dt.edit_at,
                dt.edit_comment,
                dt.errors,
                dt.merge_statuses
            FROM public.%8$I dt
            WHERE dt.row_id = ANY(%9$L)
              AND dt.action = 'use'
              AND dt.state != 'error'
              AND dt.%7$I IS NOT NULL AND char_length(trim(dt.%7$I)) > 0;
        $$,
            v_source_view_name,       -- %1$I
            v_id_select_expr,           -- %2$s
            v_select_lu_id_expr,      -- %3$s
            v_select_est_id_expr,     -- %4$s
            v_stat_def.stat_definition_id, -- %5$L
            v_stat_def.stat_type,       -- %6$L
            v_stat_def.source_col_name, -- %7$I
            v_data_table_name,          -- %8$I
            p_batch_row_ids             -- %9$L
        );
        EXECUTE v_sql;

        EXECUTE format('SELECT count(*) FROM %I', v_source_view_name) INTO v_relevant_rows_count;
        IF v_relevant_rows_count = 0 THEN
            RAISE DEBUG '[Job %] process_statistical_variables: No usable data for stat ''%'' in this batch. Skipping.', p_job_id, v_stat_def.stat_code;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] process_statistical_variables: Calling sql_saga.temporal_merge for % rows for stat ''%''.', p_job_id, v_relevant_rows_count, v_stat_def.stat_code;

        BEGIN
            CALL sql_saga.temporal_merge(
                p_target_table => 'public.stat_for_unit'::regclass,
                p_source_table => v_source_view_name::regclass,
                p_identity_columns => ARRAY['id'],
                p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                p_mode => 'MERGE_ENTITY_REPLACE',
                p_identity_correlation_column => 'founding_row_id',
                p_update_source_with_identity => true,
                p_update_source_with_feedback => true,
                p_feedback_status_column => 'merge_statuses',
                p_feedback_status_key => 'stat_' || v_stat_def.stat_code,
                p_feedback_error_column => 'errors',
                p_feedback_error_key => 'stat_' || v_stat_def.stat_code,
                p_source_row_id_column => 'row_id'
            );
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] process_statistical_variables: Error during temporal_merge for stat ''%'': %. SQLSTATE: %', p_job_id, v_stat_def.stat_code, error_message, SQLSTATE;
            -- Mark rows in this specific view as having an error for this stat
            EXECUTE format($$
                UPDATE public.%1$I dt
                SET errors = COALESCE(errors, '{}'::jsonb) || jsonb_build_object(%2$L, %3$L)
                FROM %4$I v
                WHERE dt.row_id = v.row_id;
            $$, v_data_table_name, 'stat_' || v_stat_def.stat_code, error_message, v_source_view_name);
            -- Don't re-raise, try to continue with other stats
        END;
    END LOOP;

    -- Final update to set state for any rows that accumulated errors during the loop
    v_sql := format($$
        WITH error_rows AS (
            SELECT row_id FROM public.%1$I WHERE row_id = ANY($1) AND errors IS NOT NULL
        )
        UPDATE public.%1$I dt
        SET state = 'error'
        FROM error_rows er
        WHERE dt.row_id = er.row_id;
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_row_ids;
    GET DIAGNOSTICS v_error_count = ROW_COUNT;

    -- Count total rows in batch to calculate success count
    EXECUTE format('SELECT count(*) FROM public.%1$I WHERE row_id = ANY($1)', v_data_table_name)
    INTO v_update_count USING p_batch_row_ids;
    v_update_count := v_update_count - v_error_count;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished for step %. Total rows affected: %, Errors: %',
        p_job_id, p_step_code, v_update_count, v_error_count;
END;
$process_statistical_variables$;


COMMIT;
