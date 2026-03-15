```sql
CREATE OR REPLACE PROCEDURE import.process_location(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
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
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Get step details
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] process_location: Step with code % not found in snapshot.', p_job_id, p_step_code; END IF;

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
        RAISE EXCEPTION '[Job %] process_location: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Create an updatable view over the relevant data for this step
    v_source_view_name := 'temp_loc_source_view_' || p_step_code;
    IF p_step_code = 'physical_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.physical_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'physical'::public.location_type AS type,
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.physical_address_part1 AS address_part1, dt.physical_address_part2 AS address_part2, dt.physical_address_part3 AS address_part3,
                dt.physical_postcode AS postcode, dt.physical_postplace AS postplace,
                dt.physical_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.physical_region_id) AS region_version_id, dt.physical_country_id AS country_id,
                dt.physical_latitude AS latitude, dt.physical_longitude AS longitude, dt.physical_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.batch_seq = %5$L
              AND dt.action = 'use'
              AND dt.physical_country_id IS NOT NULL
              AND (NULLIF(dt.physical_region_code_raw, '') IS NOT NULL OR NULLIF(dt.physical_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_seq            /* %5$L */
        );

    ELSIF p_step_code = 'postal_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.postal_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'postal'::public.location_type AS type,
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.postal_address_part1 AS address_part1, dt.postal_address_part2 AS address_part2, dt.postal_address_part3 AS address_part3,
                dt.postal_postcode AS postcode, dt.postal_postplace AS postplace,
                dt.postal_region_id AS region_id, (SELECT r.version_id FROM public.region r WHERE r.id = dt.postal_region_id) AS region_version_id, dt.postal_country_id AS country_id,
                dt.postal_latitude AS latitude, dt.postal_longitude AS longitude, dt.postal_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.batch_seq = %5$L
              AND dt.action = 'use'
              AND dt.postal_country_id IS NOT NULL
              AND (NULLIF(dt.postal_region_code_raw, '') IS NOT NULL OR NULLIF(dt.postal_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_seq            /* %5$L */
        );
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code %.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_location: Creating temp source view %s with SQL: %', p_job_id, v_source_view_name, v_sql;
    EXECUTE v_sql;

    v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
    RAISE DEBUG '[Job %] process_location: Counting relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_location: No usable location data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_location: Calling sql_saga.temporal_merge for % rows (step: %).', p_job_id, v_relevant_rows_count, p_step_code;

    BEGIN
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_location: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.location'::regclass,
            source_table => v_source_view_name::regclass,
            primary_identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['legal_unit_id', 'establishment_id', 'type'],
            mode => v_merge_mode,
            row_id_column => 'row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => p_step_code,
            feedback_error_column => 'errors',
            feedback_error_key => p_step_code
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->%2$L IS NOT NULL $$,
            v_data_table_name, /* %1$I */
            p_step_code        /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = (CASE WHEN dt.errors ? %3$L THEN 'error' ELSE 'processing' END)::public.import_data_state
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$,
            v_data_table_name,  /* %1$I */
            v_source_view_name, /* %2$I */
            p_step_code         /* %3$L */
        );
        RAISE DEBUG '[Job %] process_location: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_location: Merge finished for step %. Success: %, Errors: %', p_job_id, p_step_code, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during temporal_merge for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('batch_error_process_location', %2$L) WHERE dt.batch_seq = $1$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        RAISE; -- Re-throw
    END;

    RAISE DEBUG '[Job %] process_location (Batch): Finished for step %. Total Processed: %, Errors: %',
        p_job_id, p_step_code, v_update_count + v_error_count, v_error_count;
END;
$procedure$
```
