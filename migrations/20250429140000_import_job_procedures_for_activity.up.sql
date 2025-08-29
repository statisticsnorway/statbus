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
            error = CASE WHEN (dt.error - %3$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %3$L::TEXT[]) END, -- Always clear this step's error key
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

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (error ?| %2$L::text[])$$,
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
    v_snapshot JSONB;
    v_definition public.import_definition;
    v_step public.import_step;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_act_count INT := 0;
    v_updated_existing_act_count INT := 0;
    error_message TEXT;
    v_activity_type public.activity_type;
    v_category_id_col TEXT;
    v_final_id_col TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_batch_upsert_success_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_parent_id_check_sql TEXT; -- For checking if parent ID is NULL in _data table
    v_parent_unavailable_error_key TEXT;
    v_parent_unavailable_error_message TEXT;
    v_parent_check_update_count INT := 0;
    v_update_count INT; -- Declaration for v_update_count used in propagation
BEGIN
    RAISE DEBUG '[Job %] process_activity (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Get the specific step details using p_step_code from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] process_activity: Step with code % not found in snapshot. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;
    v_activity_type := CASE p_step_code -- Use p_step_code parameter directly for logic
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
    v_strategy := v_definition.strategy;
    v_edit_by_user_id := v_job.user_id;

    v_job_mode := v_definition.mode;

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
        RAISE EXCEPTION '[Job %] process_activity: Unhandled job mode % for unit ID selection. Expected one of (legal_unit, establishment_formal, establishment_informal).', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_activity: Based on mode %, using lu_id_expr: %, est_id_expr: % for table %', 
        p_job_id, v_job_mode, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name;

    -- Preliminary step: Check for missing parent unit IDs in the _data table.
    -- If a parent ID is NULL, the activity cannot be linked. Mark row as error and skip.
    IF v_job_mode = 'legal_unit' THEN
        v_parent_id_check_sql := 'dt.legal_unit_id IS NULL';
        v_parent_unavailable_error_message := format('Parent Legal Unit ID was not available when attempting to process %s.', v_activity_type);
    ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
        v_parent_id_check_sql := 'dt.establishment_id IS NULL';
        v_parent_unavailable_error_message := format('Parent Establishment ID was not available when attempting to process %s.', v_activity_type);
    ELSE
        v_parent_id_check_sql := 'TRUE'; -- Should not happen, but effectively skips if mode is unknown
        v_parent_unavailable_error_message := format('Parent unit ID for unknown mode ''%s'' was not available when attempting to process %s.', v_job_mode, v_activity_type);
    END IF;
    
    -- The error key should be the name of the input column that could not be processed.
    v_parent_unavailable_error_key := CASE v_activity_type 
                                        WHEN 'primary' THEN 'primary_activity_category_code' 
                                        ELSE 'secondary_activity_category_code' 
                                     END;

    RAISE DEBUG '[Job %] process_activity: Checking for rows where parent ID is missing using condition: %s (Error key: %s)', p_job_id, v_parent_id_check_sql, v_parent_unavailable_error_key;

    EXECUTE format($$
        UPDATE public.%1$I dt SET
            action = 'skip',
            state = 'error',
            error = COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object(%2$L, %3$L)
            -- last_completed_priority is not used in the processing phase
        WHERE dt.row_id = ANY($1)
          AND dt.action IS DISTINCT FROM 'skip' -- Only consider rows not already skipped by prior analysis steps
          AND dt.%4$I IS NOT NULL -- Only if an activity code was provided (otherwise this step is N/A for the row)
          AND (%5$s); -- The check for parent ID being NULL
    $$, v_data_table_name /* %1$I */, 
        v_parent_unavailable_error_key /* %2$L */, 
        v_parent_unavailable_error_message /* %3$L */, 
        v_category_id_col /* %4$I */, -- Check against the resolved category_id column from _data table
        v_parent_id_check_sql /* %5$s */
    ) USING p_batch_row_ids;
    GET DIAGNOSTICS v_parent_check_update_count = ROW_COUNT;
    IF v_parent_check_update_count > 0 THEN
        RAISE DEBUG '[Job %] process_activity: Marked % rows as skipped due to missing parent unit ID during processing.', p_job_id, v_parent_check_update_count;
    END IF;

    -- Step 1: Fetch batch data into a temporary table (will now exclude rows marked 'skip' above)
    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER PRIMARY KEY,
        founding_row_id INTEGER, -- Added
        legal_unit_id INT,
        establishment_id INT,
        valid_after DATE, -- Added
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        category_id INT,
        existing_act_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT, -- Added
        action public.import_row_action_type
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, legal_unit_id, establishment_id, valid_after, valid_from, valid_to, data_source_id, category_id, edit_by_user_id, edit_at, edit_comment, action -- Added edit_comment, valid_after, founding_row_id
        )
        SELECT
            row_id, founding_row_id, %1$s, %2$s, -- Use dynamic expressions for LU/EST IDs, Added founding_row_id
            derived_valid_after, -- Added
            derived_valid_from, 
            derived_valid_to,   
            data_source_id,
            %3$I, -- Select the correct category ID column based on target
            edit_by_user_id, edit_at, edit_comment, -- Added
            action 
         FROM public.%4$I dt WHERE row_id = ANY($1) AND %5$I IS NOT NULL AND action IS DISTINCT FROM 'skip'; -- Added alias dt. Only process rows with a category ID for this type and not skipped
    $$, v_select_lu_id_expr /* %1$s */, v_select_est_id_expr /* %2$s */, v_category_id_col /* %3$I */, v_data_table_name /* %4$I */, v_category_id_col /* %5$I */);
    RAISE DEBUG '[Job %] process_activity: Fetching batch data for type %: %', p_job_id, v_activity_type, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 2: Determine existing activity IDs
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_act_id = act.id
        FROM public.activity act
        WHERE act.type = %1$L -- Lookup existing activity by type and unit ID only
          AND CASE
                WHEN %2$L = 'legal_unit' THEN
                    act.legal_unit_id = tbd.legal_unit_id AND act.establishment_id IS NULL
                WHEN %3$L IN ('establishment_formal', 'establishment_informal') THEN
                    act.establishment_id = tbd.establishment_id AND act.legal_unit_id IS NULL
                ELSE FALSE -- Should not happen
              END;
    $$, v_activity_type /* %1$L */, v_job_mode /* %2$L */, v_job_mode /* %3$L */);
    RAISE DEBUG '[Job %] process_activity: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created activity_ids and their original data_row_id
    CREATE TEMP TABLE temp_created_acts (
        data_row_id INTEGER PRIMARY KEY,
        new_activity_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new activities (action = 'insert') using MERGE
        RAISE DEBUG '[Job %] process_activity: Handling INSERTS for new activities (type: %) using MERGE.', p_job_id, v_activity_type;

        WITH source_for_insert AS (
            SELECT * FROM temp_batch_data 
            WHERE action = 'insert' AND category_id IS NOT NULL
        ),
        merged_activities AS (
            MERGE INTO public.activity act
            USING source_for_insert sfi
            ON 1 = 0 -- Always false to force INSERT
            WHEN NOT MATCHED THEN
                INSERT (
                    legal_unit_id, establishment_id, type, category_id,
                    data_source_id, valid_after, valid_to, -- Changed
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    CASE WHEN v_job_mode = 'legal_unit' THEN sfi.legal_unit_id ELSE NULL END,
                    CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN sfi.establishment_id ELSE NULL END,
                    v_activity_type, sfi.category_id,
                    sfi.data_source_id, sfi.valid_after, sfi.valid_to, -- Changed
                    sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment -- Use sfi.edit_comment
                )
            RETURNING act.id AS new_activity_id, sfi.data_row_id
        )
        INSERT INTO temp_created_acts (data_row_id, new_activity_id)
        SELECT data_row_id, new_activity_id
        FROM merged_activities;

        GET DIAGNOSTICS v_inserted_new_act_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_activity: Inserted % new activities into temp_created_acts via MERGE (type: %).', p_job_id, v_inserted_new_act_count, v_activity_type;

        IF v_inserted_new_act_count > 0 THEN
            EXECUTE format($$
                UPDATE public.%1$I dt SET
                    %2$I = tca.new_activity_id,
                    error = NULL,
                    state = %3$L
                FROM temp_created_acts tca
                WHERE dt.row_id = tca.data_row_id AND dt.state != 'error';
            $$, v_data_table_name /* %1$I */, v_final_id_col /* %2$I */, 'processing'::public.import_data_state /* %3$L */);
            RAISE DEBUG '[Job %] process_activity: Updated _data table for % new activities (type: %).', p_job_id, v_inserted_new_act_count, v_activity_type;
        END IF;

        -- Propagate newly created activity_ids to other rows in temp_batch_data
        -- belonging to the same logical entity (identified by founding_row_id and unit id).
        IF v_inserted_new_act_count > 0 THEN
            RAISE DEBUG '[Job %] process_activity: Propagating new activity_ids within temp_batch_data (type: %).', p_job_id, v_activity_type;
            WITH new_entity_details AS (
                SELECT
                    tca.new_activity_id,
                    tbd_founder.founding_row_id,
                    tbd_founder.legal_unit_id,
                    tbd_founder.establishment_id
                FROM temp_created_acts tca
                JOIN temp_batch_data tbd_founder ON tca.data_row_id = tbd_founder.data_row_id
            )
            UPDATE temp_batch_data tbd
            SET existing_act_id = ned.new_activity_id
            FROM new_entity_details ned
            WHERE tbd.founding_row_id = ned.founding_row_id
              AND ( -- Match on the correct unit ID based on job mode
                    (v_job_mode = 'legal_unit' AND tbd.legal_unit_id = ned.legal_unit_id AND tbd.establishment_id IS NULL AND ned.establishment_id IS NULL) OR
                    (v_job_mode IN ('establishment_formal', 'establishment_informal') AND tbd.establishment_id = ned.establishment_id AND tbd.legal_unit_id IS NULL AND ned.legal_unit_id IS NULL)
                  )
              AND tbd.existing_act_id IS NULL -- Only update if not already set
              AND tbd.action IN ('replace', 'update'); -- Apply to subsequent actions for the same new entity
            GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Re-declare v_update_count or use a different local variable if needed for other counts
            RAISE DEBUG '[Job %] process_activity: Propagated new activity_ids to % rows in temp_batch_data (type: %).', p_job_id, v_update_count, v_activity_type;
        END IF;

        -- Handle REPLACES for existing activities (action = 'replace')
        RAISE DEBUG '[Job %] process_activity: Handling REPLACES for existing activities (type: %).', p_job_id, v_activity_type;
        -- Create temp source table for batch upsert
        CREATE TEMP TABLE temp_act_upsert_source (
            row_id INTEGER PRIMARY KEY, -- Link back to original _data row
            id INT, -- Target activity ID
            valid_after DATE NOT NULL, -- Changed
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
            row_id, id, valid_after, valid_to, legal_unit_id, establishment_id, type, category_id, -- Changed valid_from to valid_after
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, -- This becomes row_id in temp_act_upsert_source
            tbd.existing_act_id,
            tbd.valid_after, -- Changed
            tbd.valid_to,
            CASE WHEN v_job_mode = 'legal_unit' THEN tbd.legal_unit_id ELSE NULL END,
            CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN tbd.establishment_id ELSE NULL END,
            v_activity_type,
            tbd.category_id,
            tbd.data_source_id,
            tbd.edit_by_user_id,
            tbd.edit_at,
            tbd.edit_comment -- Use tbd.edit_comment
        FROM temp_batch_data tbd
        WHERE tbd.action = 'replace'; 

        GET DIAGNOSTICS v_updated_existing_act_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_activity: Populated temp_act_upsert_source with % rows for batch replace (type: %).', p_job_id, v_updated_existing_act_count, v_activity_type;

        IF v_updated_existing_act_count > 0 THEN
            RAISE DEBUG '[Job %] process_activity: Calling batch_insert_or_replace_generic_valid_time_table for activity (type: %).', p_job_id, v_activity_type;
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'activity',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_act_upsert_source',
                    p_unique_columns => '[]'::jsonb, 
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%1$I SET
                            state = %2$L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_activity_error', %3$L)
                            -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %4$L;
                    $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, v_batch_upsert_result.error_message /* %3$L */, v_batch_upsert_result.source_row_id /* %4$L */);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_activity: Batch replace finished for type %. Success: %, Errors: %', p_job_id, v_activity_type, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        %2$I = tbd.existing_act_id, 
                        error = NULL,
                        state = %3$L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id
                      AND dt.row_id = ANY($1);
                $$, v_data_table_name /* %1$I */, v_final_id_col /* %2$I */, 'processing'::public.import_data_state /* %3$L */);
                RAISE DEBUG '[Job %] process_activity: Updating _data table for successful replace rows (type: %): %', p_job_id, v_activity_type, v_sql;
                EXECUTE v_sql USING v_batch_upsert_success_row_ids;
            END IF;
        END IF;
        IF to_regclass('pg_temp.temp_act_upsert_source') IS NOT NULL THEN DROP TABLE temp_act_upsert_source; END IF;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_activity: Error during batch operation for type %: %', p_job_id, v_activity_type, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('process_activity_error', format('Error for type %s: %s', v_activity_type, error_message)),
            state = 'finished'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_activity: Marked job as failed due to error for type %: %', p_job_id, v_activity_type, error_message;
        RAISE;
    END;

    -- The framework now handles advancing priority for all rows, including unprocessed and skipped rows. No update needed here.

    RAISE DEBUG '[Job %] process_activity (Batch): Finished. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_act_count, v_updated_existing_act_count, v_error_count;

    IF to_regclass('pg_temp.temp_batch_data') IS NOT NULL THEN DROP TABLE temp_batch_data; END IF;
    IF to_regclass('pg_temp.temp_created_acts') IS NOT NULL THEN DROP TABLE temp_created_acts; END IF;
END;
$process_activity$;


COMMIT;
