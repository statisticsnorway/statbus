```sql
CREATE OR REPLACE PROCEDURE import.process_tags(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
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
    RAISE DEBUG '[Job %] process_tags (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

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
    v_sql := format($$
        SELECT count(*)
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1
          AND dt.action = 'use' AND dt.tag_id IS NOT NULL;
    $$, v_data_table_name);
    RAISE DEBUG '[Job %] process_tags: Checking for relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql
    INTO v_relevant_rows_count USING p_batch_seq;

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
        WHERE dt.batch_seq = $1
          AND dt.action = 'use'
          AND dt.tag_id IS NOT NULL;
    $$,
        v_data_table_name,    /* %1$I */
        v_select_lu_id_expr,  /* %2$s */
        v_select_est_id_expr  /* %3$s */
    );

    RAISE DEBUG '[Job %] process_tags: Populating temp source table: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

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
        v_sql := format($$
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
        RAISE DEBUG '[Job %] process_tags: Updating data table with tag_for_unit_id with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_tags: Error during batch operation: %. SQLSTATE: %', p_job_id, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I dt SET state = 'error', errors = errors || jsonb_build_object('batch_error_process_tags', %2$L) WHERE dt.batch_seq = $1$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        RAISE DEBUG '[Job %] process_tags: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_tags_error', error_message)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    RAISE DEBUG '[Job %] process_tags (Batch): Finished for step %. Total Processed: %',
        p_job_id, p_step_code, v_update_count_lu + v_update_count_est;
END;
$procedure$
```
