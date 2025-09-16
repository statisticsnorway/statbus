-- Migration: import_job_procedures_for_contact
-- Implements the analyse and operation procedures for the Contact import step.

BEGIN;

-- Procedure to analyse contact data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_contact(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_contact$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_contact (Batch): Starting analysis for range %s', p_job_id, p_batch_row_id_ranges::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'contact';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found in snapshot', p_job_id;
    END IF;

    -- This procedure now copies raw contact fields to their typed internal counterparts
    -- and advances the priority for all processed rows. The lookup for existing
    -- contact_id has been removed, as the natural key lookup will be handled
    -- by the process_contact step.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            web_address = NULLIF(dt.web_address_raw, ''),
            email_address = NULLIF(dt.email_address_raw, ''),
            phone_number = NULLIF(dt.phone_number_raw, ''),
            landline = NULLIF(dt.landline_raw, ''),
            mobile_number = NULLIF(dt.mobile_number_raw, ''),
            fax_number = NULLIF(dt.fax_number_raw, ''),
            last_completed_priority = %2$L
        WHERE dt.row_id <@ $1;
    $$,
        v_data_table_name,    /* %1$I */
        v_step.priority       /* %2$L */
    );

    RAISE DEBUG '[Job %] analyse_contact: Updating rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_contact: Processed % rows in single pass.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_contact: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_contact_batch_error', SQLERRM),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_contact: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE;
    END;

    RAISE DEBUG '[Job %] analyse_contact (Batch): Finished analysis for batch. Processed % rows.', p_job_id, v_update_count;
END;
$analyse_contact$;


-- Procedure to operate (insert/update/upsert) contact data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_contact(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
LANGUAGE plpgsql AS $process_contact$
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
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    RAISE DEBUG '[Job %] process_contact (Batch): Starting operation for range %s', p_job_id, p_batch_row_id_ranges::text;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Get step details
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] process_contact: Step with code % not found in snapshot.', p_job_id, p_step_code; END IF;

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
    ELSE
        RAISE EXCEPTION '[Job %] process_contact: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Create an updatable view over the relevant data for this step
    v_source_view_name := 'temp_contact_source_view';
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW %1$I AS
        SELECT
            dt.row_id,
            dt.founding_row_id,
            dt.contact_id AS id,
            %2$s AS legal_unit_id,
            %3$s AS establishment_id,
            dt.valid_from,
            dt.valid_to,
            dt.valid_until,
            dt.web_address, dt.email_address, dt.phone_number, dt.landline, dt.mobile_number, dt.fax_number,
            dt.data_source_id,
            dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
            dt.errors, dt.merge_status
        FROM public.%4$I dt
        WHERE dt.row_id <@ %5$L::int4multirange
          AND dt.action = 'use'
          -- Only process rows that have some actual contact data
          AND (dt.web_address IS NOT NULL OR dt.email_address IS NOT NULL OR dt.phone_number IS NOT NULL OR dt.landline IS NOT NULL OR dt.mobile_number IS NOT NULL OR dt.fax_number IS NOT NULL);
    $$,
        v_source_view_name,    /* %1$I */
        v_select_lu_id_expr,   /* %2$s */
        v_select_est_id_expr,  /* %3$s */
        v_data_table_name,     /* %4$I */
        p_batch_row_id_ranges  /* %5$L */
    );
    RAISE DEBUG '[Job %] process_contact: Creating temp source view %s with SQL: %', p_job_id, v_source_view_name, v_sql;
    EXECUTE v_sql;

    v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
    RAISE DEBUG '[Job %] process_contact: Counting relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_contact: No usable contact data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_contact: Calling sql_saga.temporal_merge for % rows.', p_job_id, v_relevant_rows_count;

    BEGIN
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch
        END;
        RAISE DEBUG '[Job %] process_contact: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.contact'::regclass,
            source_table => v_source_view_name::regclass,
            identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['legal_unit_id', 'establishment_id'],
            ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
            mode => v_merge_mode,
            identity_correlation_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'contact',
            feedback_error_column => 'errors',
            feedback_error_key => 'contact',
            source_row_id_column => 'row_id'
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I WHERE row_id <@ $1 AND errors->'contact' IS NOT NULL $$, v_data_table_name);
        RAISE DEBUG '[Job %] process_contact: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_row_id_ranges;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'contact' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$,
            v_data_table_name,  /* %1$I */
            v_source_view_name  /* %2$I */
        );
        RAISE DEBUG '[Job %] process_contact: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_contact: Merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_contact: Error during temporal_merge: %. SQLSTATE: %', p_job_id, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('batch_error_process_contact', %2$L) WHERE row_id <@ $1$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        RAISE DEBUG '[Job %] process_contact: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        RAISE; -- Re-throw
    END;

    RAISE DEBUG '[Job %] process_contact (Batch): Finished for step %. Total Processed: %, Errors: %',
        p_job_id, p_step_code, v_update_count + v_error_count, v_error_count;
END;
$process_contact$;


COMMIT;
