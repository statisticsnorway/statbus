```sql
CREATE OR REPLACE PROCEDURE import.process_statistical_variables(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
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
    v_all_stat_error_keys TEXT[];
    v_pk_id_col_name TEXT;
    v_merge_mode sql_saga.temporal_merge_mode;
    v_value_column_name TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting for batch_seq %', p_job_id, p_batch_seq;

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
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'generic_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_statistical_variables: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Find step and data column details from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;
    
    -- Filter data columns for just this step
    SELECT jsonb_agg(elem) INTO v_stat_data_cols
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') as elem
    WHERE (elem->>'step_id')::int = v_step.id;

    RAISE DEBUG '[Job %] process_statistical_variables: Data columns for step % from snapshot: %', p_job_id, p_step_code, v_stat_data_cols;

    -- Loop over each statistical variable defined for this import and process it.
    FOR v_stat_def IN
        WITH source_cols AS (
            SELECT
                replace(elem->>'column_name', '_raw', '') as stat_code
            FROM jsonb_array_elements(v_stat_data_cols) elem
            WHERE elem->>'purpose' = 'source_input'
        )
        SELECT
            sda.id as stat_definition_id,
            sda.code as stat_code,
            sda.type as stat_type
        FROM source_cols sc
        JOIN public.stat_definition_enabled sda ON sda.code = sc.stat_code
    LOOP
        RAISE DEBUG '[Job %] process_statistical_variables: Found stat variable to process: %', p_job_id, v_stat_def;

        v_source_view_name := 'temp_stat_source_view_' || v_stat_def.stat_code;
        v_pk_id_col_name := 'stat_for_unit_' || v_stat_def.stat_code || '_id';
        -- Create a dedicated, updatable VIEW for this specific statistical variable.
        -- This view MUST contain all four `value_*` columns to match the target table's
        -- business key signature, allowing sql_saga to correctly coalesce adjacent identical records.
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.%7$I AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                %4$L::INTEGER AS stat_definition_id,
                CASE WHEN %5$L = 'int'    THEN dt.%8$I ELSE NULL END AS value_int,
                CASE WHEN %5$L = 'float'  THEN dt.%8$I ELSE NULL END AS value_float,
                CASE WHEN %5$L = 'bool'   THEN dt.%8$I ELSE NULL END AS value_bool,
                CASE WHEN %5$L = 'string' THEN dt.%8$I ELSE NULL END AS value_string,
                dt.valid_from, dt.valid_to, dt.valid_until,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%6$I dt
            WHERE dt.batch_seq = %9$L
              AND dt.action = 'use'
              AND dt.%8$I IS NOT NULL;
        $$,
            v_source_view_name,           /* %1$I */
            v_select_lu_id_expr,          /* %2$s */
            v_select_est_id_expr,         /* %3$s */
            v_stat_def.stat_definition_id, /* %4$L */
            v_stat_def.stat_type,           /* %5$L */
            v_data_table_name,              /* %6$I */
            v_pk_id_col_name,             /* %7$I */
            v_stat_def.stat_code,          /* %8$I */
            p_batch_seq                    /* %9$L */
        );
        RAISE DEBUG '[Job %] process_statistical_variables: Creating source view for stat "%": %', p_job_id, v_stat_def.stat_code, v_sql;
        EXECUTE v_sql;

        v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
        RAISE DEBUG '[Job %] process_statistical_variables: Counting relevant rows for stat "%" with SQL: %', p_job_id, v_stat_def.stat_code, v_sql;
        EXECUTE v_sql INTO v_relevant_rows_count;
        IF v_relevant_rows_count = 0 THEN
            RAISE DEBUG '[Job %] process_statistical_variables: No usable data for stat ''%'' in this batch. Skipping.', p_job_id, v_stat_def.stat_code;
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] process_statistical_variables: Calling sql_saga.temporal_merge for % rows for stat ''%''.', p_job_id, v_relevant_rows_count, v_stat_def.stat_code;

        BEGIN
            v_merge_mode := CASE v_definition.strategy
                WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
                WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
                WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
                WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
                ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            END;
            RAISE DEBUG '[Job %] process_statistical_variables: Determined merge mode % for stat %', p_job_id, v_merge_mode, v_stat_def.stat_code;

            CALL sql_saga.temporal_merge(
                target_table => 'public.stat_for_unit'::regclass,
                source_table => v_source_view_name::regclass,
                primary_identity_columns => ARRAY['id'],
                natural_identity_columns => ARRAY['stat_definition_id', 'legal_unit_id', 'establishment_id'],
                mode => v_merge_mode,
                row_id_column => 'row_id',
                founding_id_column => 'founding_row_id',
                update_source_with_identity => true,
                update_source_with_feedback => true,
                feedback_status_column => 'merge_status',
                feedback_status_key => 'stat_' || v_stat_def.stat_code,
                feedback_error_column => 'errors',
                feedback_error_key => 'stat_' || v_stat_def.stat_code
            );

            -- Feedback is written directly back to the data table by sql_saga, no need for manual UPDATE.

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
            RAISE WARNING '[Job %] process_statistical_variables: Error during temporal_merge for stat ''%'': %. SQLSTATE: %', p_job_id, v_stat_def.stat_code, error_message, SQLSTATE;
            v_sql := format($$
                UPDATE public.%1$I dt
                SET errors = dt.errors || jsonb_build_object(%2$L, %3$L)
                FROM %4$I v
                WHERE dt.row_id = v.row_id;
            $$, v_data_table_name, 'stat_' || v_stat_def.stat_code, error_message, v_source_view_name);
            RAISE DEBUG '[Job %] process_statistical_variables: Marking rows as error in exception handler for stat "%" with SQL: %', p_job_id, v_stat_def.stat_code, v_sql;
            EXECUTE v_sql;
        END;
    END LOOP;

    -- Final update to set state for any rows that accumulated errors during the loop
    v_all_stat_error_keys := ARRAY(
        SELECT 'stat_' || sda.code
        FROM jsonb_array_elements(v_stat_data_cols) idc
        JOIN public.stat_definition_enabled sda ON sda.code = replace((idc.value->>'column_name'), '_raw', '')
        WHERE idc.value->>'purpose' = 'source_input'
    );

    -- Only update rows with action = 'use' to satisfy CHECK constraint:
    -- state = 'processing' requires action = 'use' AND batch_seq IS NOT NULL
    v_sql := format($$
        UPDATE public.%1$I dt
        SET state = (CASE
                        WHEN dt.errors ?| %2$L THEN 'error'
                        ELSE 'processing'
                    END)::public.import_data_state
        WHERE dt.batch_seq = $1 AND dt.action = 'use';
    $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final state update with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    v_sql := format($$SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND dt.errors ?| %2$L $$,
        v_data_table_name,       /* %1$I */
        v_all_stat_error_keys    /* %2$L */
    );
    RAISE DEBUG '[Job %] process_statistical_variables: Final error count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_error_count USING p_batch_seq;

    v_sql := format('SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1', v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Final total count with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_update_count USING p_batch_seq;
    v_update_count := v_update_count - v_error_count;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished for step %. Total rows affected: %, Errors: %',
        p_job_id, p_step_code, v_update_count, v_error_count;
END;
$procedure$
```
