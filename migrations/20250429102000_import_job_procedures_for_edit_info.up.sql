-- Implements the analyse procedure for the edit_info import step.

BEGIN;

-- Procedure to analyse edit info (populate user and timestamp) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_edit_info(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_edit_info$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_edit_info (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details (specifically user_id)
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'edit_info';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] edit_info step not found', p_job_id;
    END IF;

    -- Step 1: Batch Update edit_by_user_id and edit_at for non-skipped rows
    -- Use the user_id from the job and the current statement timestamp
    v_sql := format($$
        UPDATE public.%I dt SET
            edit_by_user_id = %L,
            edit_at = statement_timestamp(),
            edit_comment = %L, -- Set edit_comment from job's default
            last_completed_priority = %L,
            -- error = NULL, -- Removed: This step should not clear errors from prior steps
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.action IS DISTINCT FROM 'skip'; -- Process if action is distinct from 'skip' (handles NULL)
    $$, v_data_table_name, v_job.user_id, v_job.edit_comment, v_step.priority, 'analysing', p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_edit_info: Updating edit columns for non-skipped rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_edit_info: Marked % non-skipped rows as success for this step.', p_job_id, v_update_count;

    -- Update priority for skipped rows
    EXECUTE format($$UPDATE public.%I SET last_completed_priority = %L WHERE row_id = ANY(%L) AND action = 'skip'$$,
                   v_data_table_name, v_step.priority, p_batch_row_ids);
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_edit_info: Advanced priority for % skipped rows.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_edit_info (Batch): Finished analysis for batch.', p_job_id;
END;
$analyse_edit_info$;


COMMIT;
