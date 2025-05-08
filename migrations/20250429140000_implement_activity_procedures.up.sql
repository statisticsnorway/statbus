-- Migration: implement_activity_procedures
-- Implements the analyse and operation procedures for the PrimaryActivity
-- and SecondaryActivity import targets using generic activity handlers.

BEGIN;

-- Procedure to analyse activity data (handles both primary and secondary) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_activity(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_activity$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch) for step_code %: Starting analysis for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Get the specific step details using p_step_code
    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_activity: Step with code % not found. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Step 1: Batch Update Lookups
    v_sql := format($$
        UPDATE public.%I dt SET
            primary_activity_category_id = src.new_primary_activity_category_id,
            secondary_activity_category_id = src.new_secondary_activity_category_id
        FROM (
            SELECT
                dt_sub.row_id AS row_id_for_join,
                pac.id as new_primary_activity_category_id,
                sac.id as new_secondary_activity_category_id
            FROM public.%I dt_sub
            LEFT JOIN public.activity_category pac ON dt_sub.primary_activity_category_code IS NOT NULL AND pac.code = dt_sub.primary_activity_category_code
            LEFT JOIN public.activity_category sac ON dt_sub.secondary_activity_category_code IS NOT NULL AND sac.code = dt_sub.secondary_activity_category_code
            WHERE dt_sub.row_id = ANY(%L) -- Filter for the current batch
        ) AS src
        WHERE dt.row_id = src.row_id_for_join;
    $$, v_data_table_name, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_activity: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            row_id,
            jsonb_strip_nulls(
                jsonb_build_object('primary_activity_category_code', CASE WHEN primary_activity_category_code IS NOT NULL AND primary_activity_category_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('secondary_activity_category_code', CASE WHEN secondary_activity_category_code IS NOT NULL AND secondary_activity_category_id IS NULL THEN 'Not found' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L)
    $$, v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_activity: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 3: Batch Update Error Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
    $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_activity: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_activity: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 4: Batch Update Success Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - 'primary_activity_category_code' - 'secondary_activity_category_code') = '{}'::jsonb THEN NULL ELSE (dt.error - 'primary_activity_category_code' - 'secondary_activity_category_code') END, -- Clear only this step's error keys
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_activity: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_activity$;


-- Procedure to operate (insert/update/upsert) activity data (handles both primary and secondary) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_activity(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_activity$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_activity_type public.activity_type;
    v_category_id_col TEXT;
    v_final_id_col TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
    RAISE DEBUG '[Job %] process_activity (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Get the specific step details using p_step_code
    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] process_activity: Step with code % not found. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;
    v_activity_type := CASE v_step.code -- Use v_step.code
        WHEN 'primary_activity' THEN 'primary'::public.activity_type
        WHEN 'secondary_activity' THEN 'secondary'::public.activity_type
        ELSE NULL -- Should not happen
    END;

    IF v_activity_type IS NULL THEN
        RAISE EXCEPTION '[Job %] process_activity: Invalid step_code % provided for activity processing.', p_job_id, p_step_code;
    END IF;

    v_category_id_col := CASE v_activity_type WHEN 'primary' THEN 'primary_activity_category_id' ELSE 'secondary_activity_category_id' END;
    v_final_id_col := CASE v_activity_type WHEN 'primary' THEN 'primary_activity_id' ELSE 'secondary_activity_id' END;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        category_id INT,
        existing_act_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id, category_id, edit_by_user_id, edit_at
        )
        SELECT
            row_id, legal_unit_id, establishment_id,
            derived_valid_from, -- Changed to derived_valid_from
            derived_valid_to,   -- Changed to derived_valid_to
            data_source_id,
            %I, -- Select the correct category ID column based on target
            edit_by_user_id, edit_at
         FROM public.%I WHERE row_id = ANY(%L) AND %I IS NOT NULL; -- Only process rows with a category ID for this type
    $$, v_category_id_col, v_data_table_name, p_batch_row_ids, v_category_id_col);
    RAISE DEBUG '[Job %] process_activity: Fetching batch data for type %: %', p_job_id, v_activity_type, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing activity IDs
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_act_id = act.id
        FROM public.activity act
        WHERE act.type = %L
          AND act.category_id = tbd.category_id
          AND act.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND act.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    $$, v_activity_type);
    RAISE DEBUG '[Job %] process_activity: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch Upsert using admin.batch_upsert_generic_valid_time_table
    BEGIN
        -- Create temp source table for batch upsert
        CREATE TEMP TABLE temp_act_upsert_source (
            row_id BIGINT PRIMARY KEY, -- Link back to original _data row
            id INT, -- Target activity ID
            valid_from DATE NOT NULL,
            valid_to DATE NOT NULL,
            legal_unit_id INT,
            establishment_id INT,
            type public.activity_type,
            category_id INT,
            data_source_id INT,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        -- Populate temp source table
        INSERT INTO temp_act_upsert_source (
            row_id, id, valid_from, valid_to, legal_unit_id, establishment_id, type, category_id,
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id,
            tbd.existing_act_id,
            tbd.valid_from,
            tbd.valid_to,
            tbd.legal_unit_id,
            tbd.establishment_id,
            v_activity_type,
            tbd.category_id,
            tbd.data_source_id,
            tbd.edit_by_user_id,
            tbd.edit_at,
            'Import Job Batch Update/Upsert'
        FROM temp_batch_data tbd
        WHERE
            CASE v_strategy
                WHEN 'insert_only' THEN tbd.existing_act_id IS NULL
                WHEN 'update_only' THEN tbd.existing_act_id IS NOT NULL
                WHEN 'upsert' THEN TRUE
            END;

        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_activity: Populated temp_act_upsert_source with % rows for batch upsert (type: %).', p_job_id, v_update_count, v_activity_type;

        IF v_update_count > 0 THEN
            -- Call batch upsert function
            RAISE DEBUG '[Job %] process_activity: Calling batch_upsert_generic_valid_time_table for activity (type: %).', p_job_id, v_activity_type;
            FOR v_batch_upsert_result IN
                SELECT * FROM admin.batch_upsert_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'activity',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_act_upsert_source',
                    p_source_row_id_column_name => 'row_id',
                    p_unique_columns => '[]'::jsonb, -- ID is provided directly
                    p_temporal_columns => ARRAY['valid_from', 'valid_to'],
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET
                            state = %L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_upsert_activity_error', %L),
                            last_completed_priority = %L
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_activity: Batch upsert finished for type %. Success: %, Errors: %', p_job_id, v_activity_type, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            -- Update _data table for successful rows
            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%I dt SET
                        %I = tbd.existing_act_id, -- Set the correct pk_id column
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id
                      AND dt.row_id = ANY(%L);
                $$, v_data_table_name, v_final_id_col, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                RAISE DEBUG '[Job %] process_activity: Updating _data table for successful rows (type: %): %', p_job_id, v_activity_type, v_sql;
                EXECUTE v_sql;
            END IF;
        END IF; -- End if v_update_count > 0

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_activity: Error during batch operation for type %: %', p_job_id, v_activity_type, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_activity', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        UPDATE public.import_job SET error = jsonb_build_object('process_activity_error', format('Error for type %s: %s', v_activity_type, error_message)) WHERE id = p_job_id;
    END;

    -- Update priority for rows that didn't have the relevant category ID (were skipped)
     v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L) AND dt.state != %L AND %I IS NULL;
    $$, v_data_table_name, v_step.priority, p_batch_row_ids, 'error', v_category_id_col);
    EXECUTE v_sql;


    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_activity (Batch): Finished operation for batch type %. Initial batch size: %. Errors (estimated): %', p_job_id, v_activity_type, array_length(p_batch_row_ids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_act_upsert_source;
END;
$process_activity$;


COMMIT;
