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
        WITH
        batch_data AS (
            SELECT row_id, tag_path
            FROM public.%1$I
            WHERE row_id = ANY($1) AND tag_path IS NOT NULL AND action IS DISTINCT FROM 'skip'
        ),
        distinct_paths AS (
            SELECT tag_path
            FROM batch_data
            GROUP BY 1
        ),
        casted_paths AS (
            SELECT
                dp.tag_path,
                (import.safe_cast_to_ltree(dp.tag_path)).p_value AS casted_ltree_path,
                (import.safe_cast_to_ltree(dp.tag_path)).p_error_message AS ltree_error_msg
            FROM distinct_paths dp
        ),
        resolved_tags AS (
            SELECT
                cp.tag_path,
                cp.casted_ltree_path,
                cp.ltree_error_msg,
                t.id as resolved_tag_id
            FROM casted_paths cp
            LEFT JOIN public.tag t ON t.path = cp.casted_ltree_path
        ),
        lookups AS (
            SELECT
                bd.row_id,
                rt.casted_ltree_path,
                rt.ltree_error_msg,
                rt.resolved_tag_id
            FROM batch_data bd
            LEFT JOIN resolved_tags rt ON bd.tag_path = rt.tag_path
        )
        UPDATE public.%1$I dt SET
            tag_path_ltree = l.casted_ltree_path,
            tag_id = l.resolved_tag_id,
            state = CASE
                        WHEN dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN 'error'::public.import_data_state
                        WHEN dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN (dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NOT NULL) OR (dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL) THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                    END,
            errors = CASE
                        WHEN dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('tag_path', l.ltree_error_msg)
                        WHEN dt.tag_path IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN
                            dt.errors || jsonb_build_object('tag_path', 'Tag not found for path: ' || dt.tag_path)
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            invalid_codes = dt.invalid_codes,
            last_completed_priority = %3$L
        FROM lookups l
        WHERE dt.row_id = l.row_id;
    $$,
        v_data_table_name,          /* %1$I */
        v_error_keys_to_clear_arr,  /* %2$L */
        v_step.priority             /* %3$L */
    );
    RAISE DEBUG '[Job %] analyse_tags: Single-pass batch update for non-skipped rows (tag errors are fatal): %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Logic update affected % rows.', p_job_id, v_update_count;

        -- Unconditionally advance the priority for all rows in the batch that have not yet completed this step.
        -- This is crucial to ensure progress, as it covers rows that were skipped OR had no data for this step.
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.last_completed_priority < %2$L;
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;

        -- Estimate error count
        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
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
    v_definition public.import_definition;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count_lu INT := 0;
    v_update_count_est INT := 0;
    v_job_mode public.import_mode;
    error_message TEXT;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_relevant_rows_count INT;
BEGIN
    RAISE DEBUG '[Job %] process_tags (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_row_ids, 1);

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
    ELSE
        RAISE EXCEPTION '[Job %] process_tags: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Check for relevant rows before proceeding
    EXECUTE format($$
        SELECT count(*)
        FROM public.%1$I dt
        WHERE dt.row_id = ANY($1) AND dt.action = 'use' AND dt.tag_id IS NOT NULL;
    $$, v_data_table_name)
    INTO v_relevant_rows_count USING p_batch_row_ids;

    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_tags: No usable tag data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    -- Create a temp table with only the necessary data for the batch
    IF to_regclass('pg_temp.temp_tags_for_batch') IS NOT NULL THEN DROP TABLE temp_tags_for_batch; END IF;
    CREATE TEMP TABLE temp_tags_for_batch (
        row_id INTEGER PRIMARY KEY,
        tag_id INT NOT NULL,
        legal_unit_id INT,
        establishment_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_tags_for_batch (row_id, tag_id, legal_unit_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
        SELECT
            dt.row_id,
            dt.tag_id,
            %2$s,
            %3$s,
            dt.edit_by_user_id,
            dt.edit_at,
            dt.edit_comment
        FROM public.%1$I dt
        WHERE dt.row_id = ANY($1)
          AND dt.action = 'use'
          AND dt.tag_id IS NOT NULL;
    $$,
        v_data_table_name,    /* %1$I */
        v_select_lu_id_expr,  /* %2$s */
        v_select_est_id_expr  /* %3$s */
    );

    RAISE DEBUG '[Job %] process_tags: Populating temp source table: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Use two separate MERGE statements due to partial unique indexes on tag_for_unit
    BEGIN
        -- Merge for Legal Units
        MERGE INTO public.tag_for_unit AS t
        USING (SELECT * FROM temp_tags_for_batch WHERE legal_unit_id IS NOT NULL) AS s
        ON (t.tag_id = s.tag_id AND t.legal_unit_id = s.legal_unit_id)
        WHEN MATCHED AND t.edit_at < s.edit_at THEN
            UPDATE SET
                edit_by_user_id = s.edit_by_user_id,
                edit_at = s.edit_at,
                edit_comment = s.edit_comment
        WHEN NOT MATCHED THEN
            INSERT (tag_id, legal_unit_id, edit_by_user_id, edit_at, edit_comment)
            VALUES (s.tag_id, s.legal_unit_id, s.edit_by_user_id, s.edit_at, s.edit_comment);
        GET DIAGNOSTICS v_update_count_lu = ROW_COUNT;

        -- Merge for Establishments
        MERGE INTO public.tag_for_unit AS t
        USING (SELECT * FROM temp_tags_for_batch WHERE establishment_id IS NOT NULL) AS s
        ON (t.tag_id = s.tag_id AND t.establishment_id = s.establishment_id)
        WHEN MATCHED AND t.edit_at < s.edit_at THEN
            UPDATE SET
                edit_by_user_id = s.edit_by_user_id,
                edit_at = s.edit_at,
                edit_comment = s.edit_comment
        WHEN NOT MATCHED THEN
            INSERT (tag_id, establishment_id, edit_by_user_id, edit_at, edit_comment)
            VALUES (s.tag_id, s.establishment_id, s.edit_by_user_id, s.edit_at, s.edit_comment);
        GET DIAGNOSTICS v_update_count_est = ROW_COUNT;

        RAISE DEBUG '[Job %] process_tags: Merged % LU links and % EST links.', p_job_id, v_update_count_lu, v_update_count_est;

        -- Update _data table with the resulting tag_for_unit_id
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                tag_for_unit_id = tfu.id,
                state = 'processing'
            FROM temp_tags_for_batch t
            JOIN public.tag_for_unit tfu
                ON tfu.tag_id = t.tag_id
               AND tfu.legal_unit_id IS NOT DISTINCT FROM t.legal_unit_id
               AND tfu.establishment_id IS NOT DISTINCT FROM t.establishment_id
            WHERE dt.row_id = t.row_id;
        $$, v_data_table_name);

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_tags: Error during batch operation: %. SQLSTATE: %', p_job_id, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I SET state = 'error', errors = errors || jsonb_build_object('batch_error_process_tags', %2$L) WHERE row_id = ANY($1)$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        EXECUTE v_sql USING p_batch_row_ids;
        RAISE;
    END;

    RAISE DEBUG '[Job %] process_tags (Batch): Finished for step %. Total Processed: %',
        p_job_id, p_step_code, v_update_count_lu + v_update_count_est;
END;
$process_tags$;


COMMIT;
