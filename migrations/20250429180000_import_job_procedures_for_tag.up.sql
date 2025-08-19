-- Migration: import_job_procedures_for_tag
-- Implements the analyse and operation procedures for the Tags import target.

BEGIN;

-- Procedure to analyse tag data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_tags(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_tags$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['tag_path'];
    -- v_invalid_code_keys_to_clear_arr is removed as tag errors are now fatal
BEGIN
    RAISE DEBUG '[Job %] analyse_tags (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the target details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'tags';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] tags target not found in snapshot', p_job_id;
    END IF;

    -- Single-pass batch update for casting, lookup, state, error, and priority
    v_sql := format($$
        WITH casted_tags_cte AS ( -- Renamed CTE
            SELECT
                dt.row_id,
                (import.safe_cast_to_ltree(dt.tag_path)).p_value AS casted_ltree_path,
                (import.safe_cast_to_ltree(dt.tag_path)).p_error_message AS ltree_error_msg
            FROM public.%1$I dt -- v_data_table_name
            WHERE dt.row_id = ANY($1) AND dt.tag_path IS NOT NULL AND dt.action IS DISTINCT FROM 'skip' -- p_batch_row_ids
        ),
        resolved_tags AS (
            SELECT
                ctc.row_id, -- Use ctc alias
                ctc.casted_ltree_path,
                ctc.ltree_error_msg,
                t.id as resolved_tag_id
            FROM casted_tags_cte ctc -- Use ctc alias
            LEFT JOIN public.tag t ON t.path = ctc.casted_ltree_path -- Join on casted_ltree_path
        )
        UPDATE public.%1$I dt SET -- v_data_table_name
            tag_path_ltree = rt.casted_ltree_path, -- Use casted_ltree_path from resolved_tags
            tag_id = rt.resolved_tag_id,
            -- Determine state first
            state = CASE
                        WHEN dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NOT NULL THEN 'error'::public.import_data_state
                        WHEN dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NULL AND rt.resolved_tag_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            -- Then determine action based on the new state or existing action
            action = CASE
                        -- If this step causes an error, action becomes 'skip'
                        WHEN (dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NOT NULL) OR (dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NULL AND rt.resolved_tag_id IS NULL) THEN 'skip'::public.import_row_action_type
                        -- Otherwise, preserve existing action (which could be 'skip' from a prior step, or 'insert'/'replace' etc.)
                        ELSE dt.action
                    END,
            error = CASE
                        WHEN dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NOT NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('tag_path', rt.ltree_error_msg) -- Use error message from cast
                        WHEN dt.tag_path IS NOT NULL AND rt.ltree_error_msg IS NULL AND rt.resolved_tag_id IS NULL THEN
                            COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('tag_path', 'Tag not found for path: ' || dt.tag_path)
                        ELSE -- Success or no tag_path provided
                            CASE WHEN (dt.error - %2$L::TEXT[]) = '{}'::jsonb THEN NULL ELSE (dt.error - %2$L::TEXT[]) END -- v_error_keys_to_clear_arr
                    END,
            invalid_codes = dt.invalid_codes, -- Preserve existing invalid_codes as this step only produces hard errors for tags
            last_completed_priority = %3$L -- v_step.priority
        FROM (
            SELECT row_id FROM public.%1$I WHERE row_id = ANY($1) AND action IS DISTINCT FROM 'skip' -- v_data_table_name, p_batch_row_ids
        ) base
        LEFT JOIN resolved_tags rt ON base.row_id = rt.row_id
        WHERE dt.row_id = base.row_id AND dt.action IS DISTINCT FROM 'skip';
    $$,
        v_data_table_name,          -- %1$I
        v_error_keys_to_clear_arr,  -- %2$L
        v_step.priority             -- %3$L
    );
    RAISE DEBUG '[Job %] analyse_tags: Single-pass batch update for non-skipped rows (tag errors are fatal): %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Updated last_completed_priority for % skipped rows.', p_job_id, v_skipped_update_count;
        
        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected

        -- Estimate error count
        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (error ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
        RAISE DEBUG '[Job %] analyse_tags: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_tags: Error during single-pass batch update: %', p_job_id, SQLERRM;
        -- Mark the job itself as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_tags_batch_error', SQLERRM),
            state = 'finished' -- Or a new 'failed' state if introduced
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_tags: Marked job as failed due to error: %', p_job_id, SQLERRM;
        RAISE; -- Re-raise the original exception to halt processing
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, 'analyse_tags');

    RAISE DEBUG '[Job %] analyse_tags (Batch): Finished analysis for batch.', p_job_id; -- Simplified final message
END;
$analyse_tags$;




-- Procedure to operate (insert/update/upsert) tag data (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_tags(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_tags$
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
    v_sql_lu TEXT;
    v_sql_est TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_update_count_lu INT := 0;
    v_update_count_est INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_tags (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Find the target step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'tags';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] tags target not found in snapshot', p_job_id;
    END IF;

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
        RAISE EXCEPTION '[Job %] process_tags: Unhandled job mode % for unit ID selection. Expected one of (legal_unit, establishment_formal, establishment_informal).', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_tags: Based on mode %, using lu_id_expr: %, est_id_expr: % for table %', 
        p_job_id, v_job_mode, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        tag_id INT,
        existing_link_id INT,
        edit_comment TEXT, -- Added
        action public.import_row_action_type 
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (data_row_id, legal_unit_id, establishment_id, tag_id, edit_comment, action) 
        SELECT row_id, %1$s, %2$s, tag_id, edit_comment, action 
        FROM public.%3$I dt WHERE row_id = ANY($1) AND tag_id IS NOT NULL AND action != 'skip'; -- Added alias dt
    $$, v_select_lu_id_expr /* %1$s */, v_select_est_id_expr /* %2$s */, v_data_table_name /* %3$I */);
    RAISE DEBUG '[Job %] process_tags: Fetching batch data: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Step 2: Determine existing link IDs (tag_for_unit)
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_link_id = tfu.id
        FROM public.tag_for_unit tfu
        WHERE tfu.tag_id = tbd.tag_id
          AND tfu.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND tfu.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    $$);
    RAISE DEBUG '[Job %] process_tags: Determining existing link IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT/UPDATE/UPSERT on tag_for_unit
    -- Since tag_for_unit is NOT temporal, we handle operations directly.
    BEGIN
        v_update_count := 0; -- Reset counter

        -- Handle based on strategy
        IF v_strategy = 'insert_only' THEN
            -- Insert Legal Units
            v_sql_lu := format($$
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
                SELECT tbd.tag_id, 
                       tbd.legal_unit_id, -- Directly use tbd.legal_unit_id
                       NULL,              -- establishment_id must be NULL for LU tag
                       dt.edit_by_user_id, dt.edit_at, tbd.edit_comment
                FROM temp_batch_data tbd JOIN public.%1$I dt ON tbd.data_row_id = dt.row_id
                WHERE tbd.action = 'insert' AND tbd.legal_unit_id IS NOT NULL AND tbd.existing_link_id IS NULL; -- Only insert new LU links
            $$, v_data_table_name /* %1$I */);
            RAISE DEBUG '[Job %] process_tags (insert_only LU): %', p_job_id, v_sql_lu;
            EXECUTE v_sql_lu;
            GET DIAGNOSTICS v_update_count_lu = ROW_COUNT;
            v_update_count := v_update_count + v_update_count_lu;

            -- Insert Establishments
            v_sql_est := format($$
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
                SELECT tbd.tag_id,
                       NULL,              -- legal_unit_id must be NULL for EST tag
                       tbd.establishment_id, -- Directly use tbd.establishment_id
                       dt.edit_by_user_id, dt.edit_at, tbd.edit_comment
                FROM temp_batch_data tbd JOIN public.%1$I dt ON tbd.data_row_id = dt.row_id
                WHERE tbd.action = 'insert' AND tbd.establishment_id IS NOT NULL AND tbd.existing_link_id IS NULL; -- Only insert new EST links
            $$, v_data_table_name /* %1$I */);
            RAISE DEBUG '[Job %] process_tags (insert_only EST): %', p_job_id, v_sql_est;
            EXECUTE v_sql_est;
            GET DIAGNOSTICS v_update_count_est = ROW_COUNT;
            v_update_count := v_update_count + v_update_count_est;

        ELSIF v_strategy = 'replace_only' THEN
            -- Update based on existing_link_id, regardless of unit type (audit info update)
            v_sql := format($$
                UPDATE public.tag_for_unit tfu SET
                    edit_by_user_id = dt.edit_by_user_id, edit_at = dt.edit_at, edit_comment = tbd.edit_comment
                FROM temp_batch_data tbd JOIN public.%1$I dt ON tbd.data_row_id = dt.row_id
                WHERE tfu.id = tbd.existing_link_id AND tbd.action = 'replace'; -- Only update if action is replace and link exists
            $$, v_data_table_name /* %1$I */);
            RAISE DEBUG '[Job %] process_tags (replace_only): %', p_job_id, v_sql;
            EXECUTE v_sql;
            GET DIAGNOSTICS v_update_count = ROW_COUNT;

        ELSIF v_strategy = 'insert_or_replace' THEN
            -- Upsert for Legal Units using partial index constraint
            v_sql_lu := format($$
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
                SELECT tbd.tag_id,
                       tbd.legal_unit_id, -- Directly use tbd.legal_unit_id
                       NULL, -- establishment_id is NULL for LU-specific constraint
                       dt.edit_by_user_id, dt.edit_at, tbd.edit_comment
                FROM temp_batch_data tbd JOIN public.%1$I dt ON tbd.data_row_id = dt.row_id
                WHERE tbd.action IN ('insert', 'replace') AND tbd.legal_unit_id IS NOT NULL
                ON CONFLICT (tag_id, legal_unit_id) WHERE legal_unit_id IS NOT NULL DO UPDATE SET
                    edit_by_user_id = EXCLUDED.edit_by_user_id,
                    edit_at = EXCLUDED.edit_at,
                    edit_comment = EXCLUDED.edit_comment;
            $$, v_data_table_name /* %1$I */);
            RAISE DEBUG '[Job %] process_tags (insert_or_replace LU): %', p_job_id, v_sql_lu;
            EXECUTE v_sql_lu;
            GET DIAGNOSTICS v_update_count_lu = ROW_COUNT;
            v_update_count := v_update_count + v_update_count_lu;

            -- Upsert for Establishments using partial index constraint
            v_sql_est := format($$
                INSERT INTO public.tag_for_unit (tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
                SELECT tbd.tag_id,
                       NULL, -- legal_unit_id is NULL for EST-specific constraint
                       tbd.establishment_id, -- Directly use tbd.establishment_id
                       dt.edit_by_user_id, dt.edit_at, tbd.edit_comment
                FROM temp_batch_data tbd JOIN public.%1$I dt ON tbd.data_row_id = dt.row_id
                WHERE tbd.action IN ('insert', 'replace') AND tbd.establishment_id IS NOT NULL
                ON CONFLICT (tag_id, establishment_id) WHERE establishment_id IS NOT NULL DO UPDATE SET
                    edit_by_user_id = EXCLUDED.edit_by_user_id,
                    edit_at = EXCLUDED.edit_at,
                    edit_comment = EXCLUDED.edit_comment;
            $$, v_data_table_name /* %1$I */);
            RAISE DEBUG '[Job %] process_tags (insert_or_replace EST): %', p_job_id, v_sql_est;
            EXECUTE v_sql_est;
            GET DIAGNOSTICS v_update_count_est = ROW_COUNT;
            v_update_count := v_update_count + v_update_count_est;
        END IF;

        RAISE DEBUG '[Job %] process_tags: Total rows affected by % strategy: %', p_job_id, v_strategy, v_update_count;

        -- Step 3b: Update _data table with resulting tag_for_unit_id (Post-operation)
        -- This lookup should still work as it joins on tag_id and the specific unit IDs
        v_sql := format($$
            WITH link_lookup AS (
                 SELECT id as link_id, tag_id, legal_unit_id, establishment_id
                 FROM public.tag_for_unit
            )
            UPDATE public.%1$I dt SET
                tag_for_unit_id = ll.link_id,
                error = NULL -- Clears any error previously set by this step if now successful
                -- State remains 'processing' as set by the calling procedure for this phase
            FROM temp_batch_data tbd
            JOIN link_lookup ll ON ll.tag_id = tbd.tag_id
                               AND ll.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
                               AND ll.establishment_id IS NOT DISTINCT FROM tbd.establishment_id
            WHERE dt.row_id = tbd.data_row_id
              AND dt.state != %2$L -- Do not update if row is already in 'error' state from a prior step or this one.
              AND tbd.action IN ('insert', 'replace'); -- Only update rows that were processed by this step's DML
        $$, v_data_table_name /* %1$I */, 'error' /* %2$L */);
        RAISE DEBUG '[Job %] process_tags: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_tags: Error during batch operation: %', p_job_id, error_message;
        -- Update job error
        UPDATE public.import_job
        SET error = jsonb_build_object('process_tags_error', error_message),
            state = 'finished' -- Or a new 'failed' state
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_tags: Marked job as failed due to error: %', p_job_id, error_message;
        DROP TABLE IF EXISTS temp_batch_data;
        RAISE; -- Re-raise the original exception
    END;

    RAISE DEBUG '[Job %] process_tags (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_row_ids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
END;
$process_tags$;


COMMIT;
