```sql
CREATE OR REPLACE PROCEDURE import.analyse_tags(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['tag_path_raw'];
    -- v_invalid_code_keys_to_clear_arr is removed as tag errors are now fatal
BEGIN
    RAISE DEBUG '[Job %] analyse_tags (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

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
            SELECT dt.row_id, dt.tag_path_raw AS tag_path
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1
              AND dt.tag_path_raw IS NOT NULL AND dt.action IS DISTINCT FROM 'skip'
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
            tag_path = l.casted_ltree_path,
            tag_id = l.resolved_tag_id,
            state = CASE
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN 'error'::public.import_data_state
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN (dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL) OR (dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL) THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                    END,
            errors = CASE
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('tag_path_raw', l.ltree_error_msg)
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN
                            dt.errors || jsonb_build_object('tag_path_raw', 'Tag not found for path: ' || dt.tag_path_raw)
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            warnings = dt.warnings,
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
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Logic update affected % rows.', p_job_id, v_update_count;

        -- Estimate error count
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_tags: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_tags: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_tags: Error during single-pass batch update: %', p_job_id, SQLERRM;
        -- Mark the job itself as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_tags_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_tags: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance the priority for all rows in the batch that have not yet completed this step.
    -- This is crucial to ensure progress, as it covers rows that were skipped OR had no data for this step.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_tags: Unconditionally advancing priority with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_tags: Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_tags');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_tags: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_tags (Batch): Finished analysis for batch.', p_job_id; -- Simplified final message
END;
$procedure$
```
