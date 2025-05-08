-- Migration: implement_stats_procedures
-- Implements the analyse and operation procedures for the statistical_variables import target.

BEGIN;

-- Helper function for safe integer casting
CREATE OR REPLACE FUNCTION admin.safe_cast_to_integer(p_text_value TEXT)
RETURNS INTEGER LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_value::INTEGER;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid integer format: "%". Returning NULL.', p_text_value;
    RETURN NULL;
END;
$$;

-- Helper function for safe boolean casting
CREATE OR REPLACE FUNCTION admin.safe_cast_to_boolean(p_text_value TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_value::BOOLEAN;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid boolean format: "%". Returning NULL.', p_text_value;
    RETURN NULL;
END;
$$;

-- Procedure to analyse statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_statistical_variables$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_snapshot JSONB;
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_error_check_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
BEGIN
    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    -- Filter data columns relevant to this step (purpose = 'source_input' and step_id matches)
    SELECT jsonb_agg(value) INTO v_stat_data_cols
    FROM jsonb_array_elements(v_stat_data_cols) value
    WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input';

    IF v_stat_data_cols IS NULL OR jsonb_array_length(v_stat_data_cols) = 0 THEN
         RAISE DEBUG '[Job %] analyse_statistical_variables: No stat source_input data columns found in snapshot for step %. Skipping analysis.', p_job_id, v_step.id;
         EXECUTE format('UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)',
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    -- Step 1: Identify and Aggregate Errors (Type Validation)
    -- Build the error checking logic dynamically based on snapshot columns and stat_definition types
    v_add_separator := FALSE;
    FOR v_col_rec IN
        SELECT
            dc.value->>'column_name' as col_name,
            sda.type -- Use 'type' column from stat_definition_active
        FROM jsonb_array_elements(v_stat_data_cols) dc
        JOIN public.stat_definition_active sda ON sda.code = dc.value->>'column_name' -- Join to get expected type
    LOOP
        IF v_add_separator THEN v_error_check_sql := v_error_check_sql || ' || '; END IF;
        v_error_check_sql := v_error_check_sql || format(
            'jsonb_build_object(%L, CASE WHEN %I IS NOT NULL AND admin.safe_cast_to_%s(%I) IS NULL THEN ''Invalid format'' ELSE NULL END)',
            v_col_rec.col_name, -- Key for error JSON
            v_col_rec.col_name, -- Column to check
            CASE v_col_rec.type -- Use 'type' from v_col_rec
                WHEN 'int' THEN 'integer'
                WHEN 'float' THEN 'numeric'
                WHEN 'bool' THEN 'boolean'
                ELSE 'text' -- Assume 'string' or others need no casting check
            END,
            v_col_rec.col_name -- Column to cast
        );
        v_add_separator := TRUE;
    END LOOP;

    CREATE TEMP TABLE temp_batch_errors (data_row_id BIGINT PRIMARY KEY, error_jsonb JSONB)
    ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_row_id, error_jsonb)
        SELECT
            row_id,
            jsonb_strip_nulls(%s) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L) AND action != ''skip'' -- Skip rows marked for skipping
    ', v_error_check_sql, v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_statistical_variables: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 2: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.data_row_id AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 3: Batch Update Success Rows
    DECLARE
        v_stat_keys_to_remove TEXT := '';
        v_stat_key_sep TEXT := '';
    BEGIN
        FOR v_col_rec IN
            SELECT dc.value->>'column_name' as col_name
            FROM jsonb_array_elements(v_stat_data_cols) dc
            JOIN public.stat_definition sd ON sd.code = dc.value->>'column_name'
        LOOP
            v_stat_keys_to_remove := v_stat_keys_to_remove || v_stat_key_sep || '''' || (v_col_rec.col_name) || '''';
            v_stat_key_sep := ' - ';
        END LOOP;

        IF v_stat_keys_to_remove = '' THEN -- Should not happen if v_stat_data_cols is not empty
            v_stat_keys_to_remove := ''''''; -- Avoid syntax error with empty subtraction
        END IF;

        v_sql := format('
            UPDATE public.%I dt SET
                last_completed_priority = %L,
                error = CASE WHEN (dt.error - %s) = ''{}''::jsonb THEN NULL ELSE (dt.error - %s) END, -- Clear only this step''s error keys
                state = %L
            WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L) AND dt.action != ''skip''; -- Update only non-error, non-skipped rows
        ', v_data_table_name, v_step.priority, v_stat_keys_to_remove, v_stat_keys_to_remove, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    END;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_statistical_variables: Marked % rows as success for this target.', p_job_id, v_update_count;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_statistical_variables (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_statistical_variables$;


-- Procedure to operate (insert/update/upsert) statistical variable data (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_statistical_variables$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_stat_data_cols JSONB;
    v_col_rec RECORD;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_stat_count INT := 0;
    v_updated_existing_stat_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_unpivot_sql TEXT := '';
    v_add_separator BOOLEAN := FALSE;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_pk_col_name TEXT;
    v_stat_def RECORD;
    v_update_pk_sql TEXT := '';
    v_update_pk_sep TEXT := '';
BEGIN
    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column
    v_stat_data_cols := v_job.definition_snapshot->'import_data_column_list'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' OR
       v_stat_data_cols IS NULL OR jsonb_typeof(v_stat_data_cols) != 'array' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition or import_data_column_list from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'statistical_variables';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] statistical_variables target not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    -- Filter data columns relevant to this step and build unpivot logic
    v_add_separator := FALSE;
    FOR v_col_rec IN SELECT value->>'column_name' as col_name
                     FROM jsonb_array_elements(v_stat_data_cols) value -- Added alias 'value' here
                     WHERE (value->>'step_id')::int = v_step.id AND value->>'purpose' = 'source_input' -- Changed target_id to step_id
    LOOP
        IF v_add_separator THEN v_unpivot_sql := v_unpivot_sql || ' UNION ALL '; END IF;
        v_unpivot_sql := v_unpivot_sql || format($$SELECT %L AS stat_code, dt.%I AS stat_value, dt.row_id FROM public.%I dt WHERE dt.%I IS NOT NULL AND dt.row_id = ANY(%L) AND dt.action != 'skip'$$, -- Skip rows marked for skipping
                                                 v_col_rec.col_name, v_col_rec.col_name, v_data_table_name, v_col_rec.col_name, p_batch_row_ids);
        v_add_separator := TRUE;
    END LOOP;

    IF v_unpivot_sql = '' THEN
         RAISE DEBUG '[Job %] process_statistical_variables: No stat data columns found in snapshot for target % or all rows skipped. Skipping operation.', p_job_id, v_step.id;
         EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                        v_data_table_name, v_step.priority, p_batch_row_ids);
         RETURN;
    END IF;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Unpivot and Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_row_id BIGINT,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        stat_definition_id INT,
        stat_value TEXT,
        existing_link_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        action public.import_row_action_type, -- Added action
        PRIMARY KEY (data_row_id, stat_definition_id) -- Ensure uniqueness per row/stat
    ) ON COMMIT DROP;

    v_sql := format($$
        WITH unpivoted_stats AS ( %s )
        INSERT INTO temp_batch_data (
            data_row_id, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id,
            stat_definition_id, stat_value, edit_by_user_id, edit_at, action -- Added action
        )
        SELECT
            up.data_row_id, dt.legal_unit_id, dt.establishment_id,
            dt.derived_valid_from, -- Changed to derived_valid_from
            dt.derived_valid_to,   -- Changed to derived_valid_to
            dt.data_source_id,
            sd.id, up.stat_value,
            dt.edit_by_user_id, dt.edit_at,
            dt.action -- Added action
        FROM unpivoted_stats up
        JOIN public.%I dt ON up.data_row_id = dt.row_id
        JOIN public.stat_definition sd ON sd.code = up.stat_code; -- Join to get definition ID
    $$, v_unpivot_sql, v_data_table_name);
    RAISE DEBUG '[Job %] process_statistical_variables: Fetching and unpivoting batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing link IDs (stat_for_unit)
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_link_id = sfu.id
        FROM public.stat_for_unit sfu
        WHERE sfu.stat_definition_id = tbd.stat_definition_id -- Use stat_definition_id
          AND sfu.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND sfu.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    $$);
    RAISE DEBUG '[Job %] process_statistical_variables: Determining existing link IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created stat_for_unit IDs
    CREATE TEMP TABLE temp_created_stats (
        data_row_id BIGINT,
        stat_definition_id INT,
        new_stat_for_unit_id INT NOT NULL,
        PRIMARY KEY (data_row_id, stat_definition_id)
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new stats (action = 'insert')
        RAISE DEBUG '[Job %] process_statistical_variables: Handling INSERTS for new stats.', p_job_id;

        WITH rows_to_insert_stat_with_temp_key AS (
            SELECT *, row_number() OVER (PARTITION BY data_row_id ORDER BY stat_definition_id) as temp_insert_key
            FROM temp_batch_data
            WHERE action = 'insert'
        ),
        inserted_stats AS (
            INSERT INTO public.stat_for_unit (
                stat_definition_id, legal_unit_id, establishment_id, value,
                data_source_id, valid_from, valid_to,
                edit_by_user_id, edit_at, edit_comment
            )
            SELECT
                rti.stat_definition_id, rti.legal_unit_id, rti.establishment_id, rti.stat_value,
                rti.data_source_id, rti.valid_from, rti.valid_to,
                rti.edit_by_user_id, rti.edit_at, 'Import Job Batch Insert Stat'
            FROM rows_to_insert_stat_with_temp_key rti
            ORDER BY rti.data_row_id, rti.temp_insert_key -- Ensure deterministic order for RETURNING
            RETURNING id, stat_definition_id
        )
        INSERT INTO temp_created_stats (data_row_id, stat_definition_id, new_stat_for_unit_id)
        SELECT rtiwtk.data_row_id, ist.stat_definition_id, ist.id
        FROM rows_to_insert_stat_with_temp_key rtiwtk
        JOIN (SELECT id, stat_definition_id, row_number() OVER (PARTITION BY data_row_id ORDER BY stat_definition_id) as rn FROM inserted_stats) ist -- Need to reconstruct the key
        ON rtiwtk.data_row_id = ist.data_row_id AND rtiwtk.temp_insert_key = ist.rn; -- This join might be complex if multiple stats per row_id

        GET DIAGNOSTICS v_inserted_new_stat_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_statistical_variables: Inserted % new stat_for_unit records into temp_created_stats.', p_job_id, v_inserted_new_stat_count;

        -- Update _data table with resulting pk_ids for inserted stats
        IF v_inserted_new_stat_count > 0 THEN
            v_update_pk_sql := format('UPDATE public.%I dt SET last_completed_priority = %L, error = NULL, state = %L',
                                      v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
            v_update_pk_sep := ', ';

            FOR v_stat_def IN SELECT id, code FROM public.stat_definition
            LOOP
                v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
                -- Check if the dynamic pk_id column exists in the snapshot for safety
                IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_stat_data_cols) val
                           WHERE val->>'column_name' = v_pk_col_name AND val->>'purpose' = 'pk_id' AND (val->>'step_id')::int = v_step.id)
                THEN
                    v_update_pk_sql := v_update_pk_sql || v_update_pk_sep || format(
                        '%I = COALESCE(tcs.new_stat_for_unit_id, dt.%I)', -- Set if found in temp_created_stats, otherwise keep existing
                        v_pk_col_name, v_pk_col_name
                    );
                END IF;
            END LOOP;

            v_update_pk_sql := v_update_pk_sql || format(
                ' FROM temp_created_stats tcs WHERE dt.row_id = tcs.data_row_id AND dt.state != %L', 'error'
            );

            RAISE DEBUG '[Job %] process_statistical_variables: Updating _data table with final IDs for inserts: %', p_job_id, v_update_pk_sql;
            EXECUTE v_update_pk_sql;
        END IF;

        -- Handle REPLACES for existing stats using batch_insert_or_replace_generic_valid_time_table (action = 'replace')
        RAISE DEBUG '[Job %] process_statistical_variables: Handling REPLACES for existing stats via batch_upsert.', p_job_id;
        -- Create temp source table for batch upsert
        CREATE TEMP TABLE temp_stat_upsert_source (
            row_id BIGINT, -- Link back to original _data row + stat_def_id
            id INT, -- Target stat_for_unit ID
            valid_from DATE NOT NULL,
            valid_to DATE NOT NULL,
            stat_definition_id INT,
            legal_unit_id INT,
            establishment_id INT,
            value TEXT,
            data_source_id INT,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT,
            PRIMARY KEY (row_id, stat_definition_id) -- Composite key needed
        ) ON COMMIT DROP;

        -- Populate temp source table (only for 'replace' actions)
        INSERT INTO temp_stat_upsert_source (
            row_id, id, valid_from, valid_to, stat_definition_id, legal_unit_id, establishment_id, value,
            data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, -- Use data_row_id from temp_batch_data
            tbd.existing_link_id,
            tbd.valid_from,
            tbd.valid_to,
            tbd.stat_definition_id,
            tbd.legal_unit_id,
            tbd.establishment_id,
            tbd.stat_value,
            tbd.data_source_id,
            tbd.edit_by_user_id,
            tbd.edit_at,
            'Import Job Batch Replace' -- Changed comment
        FROM temp_batch_data tbd
        WHERE tbd.action = 'replace'; -- Filter by action

        GET DIAGNOSTICS v_updated_existing_stat_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_statistical_variables: Populated temp_stat_upsert_source with % rows for batch replace.', p_job_id, v_updated_existing_stat_count;

        IF v_updated_existing_stat_count > 0 THEN
            -- Call batch upsert function
            RAISE DEBUG '[Job %] process_statistical_variables: Calling batch_insert_or_replace_generic_valid_time_table for stat_for_unit.', p_job_id;
            FOR v_batch_upsert_result IN
                SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'stat_for_unit',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_stat_upsert_source',
                    p_source_row_id_column_name => 'row_id', -- This needs careful handling as source row_id is not unique here
                    p_unique_columns => '[]'::jsonb, -- ID is provided directly
                    p_temporal_columns => ARRAY['valid_from', 'valid_to'],
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                -- Need to handle the fact that source_row_id from batch result refers to data_row_id
                -- We need to update the _data table based on this data_row_id
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET
                            state = %L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_stat_error', %L),
                            last_completed_priority = %L
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_statistical_variables: Batch replace finished. Success: %, Errors: %', p_job_id, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            -- Update _data table for successful replace rows
            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_update_pk_sql := format('UPDATE public.%I dt SET last_completed_priority = %L, error = NULL, state = %L',
                                          v_data_table_name, v_step.priority, 'processing'::public.import_data_state);
                v_update_pk_sep := ', ';

                FOR v_stat_def IN SELECT id, code FROM public.stat_definition
                LOOP
                    v_pk_col_name := format('stat_for_unit_%s_id', v_stat_def.code);
                    -- Check if the dynamic pk_id column exists in the snapshot for safety
                    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_stat_data_cols) val
                               WHERE val->>'column_name' = v_pk_col_name AND val->>'purpose' = 'pk_id' AND (val->>'step_id')::int = v_step.id)
                    THEN
                        v_update_pk_sql := v_update_pk_sql || v_update_pk_sep || format(
                            '%I = COALESCE((SELECT tbd.existing_link_id FROM temp_batch_data tbd WHERE tbd.data_row_id = dt.row_id AND tbd.stat_definition_id = %L), dt.%I)',
                            v_pk_col_name, v_stat_def.id, v_pk_col_name -- Set if found in temp_batch_data for this stat_def, otherwise keep existing
                        );
                    END IF;
                END LOOP;

                v_update_pk_sql := v_update_pk_sql || format(' WHERE dt.row_id = ANY(%L) AND dt.state != %L', v_batch_upsert_success_row_ids, 'error');

                RAISE DEBUG '[Job %] process_statistical_variables: Updating _data table with final IDs for replaces: %', p_job_id, v_update_pk_sql;
                EXECUTE v_update_pk_sql;
            END IF;
        END IF; -- End if v_updated_existing_stat_count > 0

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_statistical_variables: Error during batch operation: %', p_job_id, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_stats', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        UPDATE public.import_job SET error = jsonb_build_object('process_statistical_variables_error', error_message) WHERE id = p_job_id;
    END;

     -- Update priority for rows that didn't have any stat variables or were not processed by insert/replace
     v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L)
          AND dt.action != 'skip'
          AND dt.state != 'error'
          AND NOT EXISTS (SELECT 1 FROM temp_created_stats tcs WHERE tcs.data_row_id = dt.row_id) -- Not inserted
          AND NOT EXISTS (SELECT 1 FROM temp_stat_upsert_source tsus WHERE tsus.row_id = dt.row_id); -- Not replaced
    $$, v_data_table_name, v_step.priority, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_statistical_variables: Updating priority for unprocessed rows: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_job.data_table_name, v_step.priority, p_batch_row_ids);

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_statistical_variables (Batch): Finished operation for batch. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_stat_count, v_updated_existing_stat_count, v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_created_stats;
    DROP TABLE IF EXISTS temp_stat_upsert_source;
END;
$process_statistical_variables$;


COMMIT;
