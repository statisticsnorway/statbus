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
        WHERE dt.row_id = src.row_id_for_join AND dt.action != 'skip'; -- Skip rows marked for skipping
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
        WHERE row_id = ANY(%L) AND action != 'skip' -- Skip rows marked for skipping
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
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L) AND dt.action != 'skip'; -- Update only non-error, non-skipped rows
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_activity: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Marked % rows as success for this target.', p_job_id, v_update_count;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);

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
    v_inserted_new_act_count INT := 0;
    v_updated_existing_act_count INT := 0;
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
        edit_at TIMESTAMPTZ,
        action public.import_row_action_type
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id, category_id, edit_by_user_id, edit_at, action
        )
        SELECT
            row_id, legal_unit_id, establishment_id,
            derived_valid_from, 
            derived_valid_to,   
            data_source_id,
            %I, -- Select the correct category ID column based on target
            edit_by_user_id, edit_at,
            action 
         FROM public.%I WHERE row_id = ANY(%L) AND %I IS NOT NULL AND action != 'skip'; -- Only process rows with a category ID for this type and not skipped
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

    -- Temp table to store newly created activity_ids and their original data_row_id
    CREATE TEMP TABLE temp_created_acts (
        data_row_id BIGINT PRIMARY KEY,
        new_activity_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new activities (action = 'insert')
        RAISE DEBUG '[Job %] process_activity: Handling INSERTS for new activities (type: %).', p_job_id, v_activity_type;

        WITH rows_to_insert_act_with_temp_key AS (
            SELECT *, row_number() OVER () as temp_insert_key
            FROM temp_batch_data
            WHERE action = 'insert'
            AND category_id IS NOT NULL -- Ensure category_id is present (already filtered in temp_batch_data population, but good for clarity)
        ),
        inserted_activities AS (
            INSERT INTO public.activity (
                legal_unit_id, establishment_id, type, category_id,
                data_source_id, valid_from, valid_to,
                edit_by_user_id, edit_at, edit_comment
            )
            SELECT
                rti.legal_unit_id, rti.establishment_id, v_activity_type, rti.category_id,
                rti.data_source_id, rti.valid_from, rti.valid_to,
                rti.edit_by_user_id, rti.edit_at, 'Import Job Batch Insert Activity'
            FROM rows_to_insert_act_with_temp_key rti
            ORDER BY rti.temp_insert_key
            RETURNING id
        )
        INSERT INTO temp_created_acts (data_row_id, new_activity_id)
        SELECT rtiwtk.data_row_id, ia.id
        FROM rows_to_insert_act_with_temp_key rtiwtk
        JOIN (SELECT id, row_number() OVER () as rn FROM inserted_activities) ia
        ON rtiwtk.temp_insert_key = ia.rn;

        GET DIAGNOSTICS v_inserted_new_act_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_activity: Inserted % new activities into temp_created_acts (type: %).', p_job_id, v_inserted_new_act_count, v_activity_type;

        IF v_inserted_new_act_count > 0 THEN
            EXECUTE format($$
                UPDATE public.%I dt SET
                    %I = tca.new_activity_id,
                    last_completed_priority = %L,
                    error = NULL,
                    state = %L
                FROM temp_created_acts tca
                WHERE dt.row_id = tca.data_row_id AND dt.state != 'error';
            $$, v_data_table_name, v_final_id_col, v_step.priority, 'processing'::public.import_data_state);
            RAISE DEBUG '[Job %] process_activity: Updated _data table for % new activities (type: %).', p_job_id, v_inserted_new_act_count, v_activity_type;
        END IF;

        -- Handle REPLACES for existing activities (action = 'replace')
        RAISE DEBUG '[Job %] process_activity: Handling REPLACES for existing activities (type: %).', p_job_id, v_activity_type;
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

        -- Populate temp source table (only for 'replace' actions)
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
            'Import Job Batch Replace Activity'
        FROM temp_batch_data tbd
        WHERE tbd.action = 'replace'; 

        GET DIAGNOSTICS v_updated_existing_act_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_activity: Populated temp_act_upsert_source with % rows for batch replace (type: %).', p_job_id, v_updated_existing_act_count, v_activity_type;

        IF v_updated_existing_act_count > 0 THEN
            RAISE DEBUG '[Job %] process_activity: Calling batch_insert_or_replace_generic_valid_time_table for activity (type: %).', p_job_id, v_activity_type;
            FOR v_batch_upsert_result IN
                SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'activity',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_act_upsert_source',
                    p_source_row_id_column_name => 'row_id',
                    p_unique_columns => '[]'::jsonb, 
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
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_activity_error', %L),
                            last_completed_priority = %L
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_activity: Batch replace finished for type %. Success: %, Errors: %', p_job_id, v_activity_type, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%I dt SET
                        %I = tbd.existing_act_id, 
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id
                      AND dt.row_id = ANY(%L);
                $$, v_data_table_name, v_final_id_col, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                RAISE DEBUG '[Job %] process_activity: Updating _data table for successful replace rows (type: %): %', p_job_id, v_activity_type, v_sql;
                EXECUTE v_sql;
            END IF;
        END IF;
        DROP TABLE IF EXISTS temp_act_upsert_source;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_activity: Error during batch operation for type %: %', p_job_id, v_activity_type, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_activity', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        UPDATE public.import_job SET error = jsonb_build_object('process_activity_error', format('Error for type %s: %s', v_activity_type, error_message)) WHERE id = p_job_id;
    END;

    -- Update priority for rows in the original batch that were not processed by insert or replace,
    -- and are not in an error state from this step.
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action != 'skip'
          AND dt.state != 'error' 
          AND %I IS NULL; 
    $$, v_data_table_name, v_step.priority, p_batch_row_ids, v_final_id_col);
    RAISE DEBUG '[Job %] process_activity: Updating priority for unprocessed rows (type: %): %', p_job_id, v_activity_type, v_sql;
    EXECUTE v_sql;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_job.data_table_name, v_step.priority, p_batch_row_ids);

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_activity (Batch): Finished. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_act_count, v_updated_existing_act_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_acts;
END;
$process_activity$;


COMMIT;
