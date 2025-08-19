-- Implements the analyse procedure for the edit_info import step.

BEGIN;

-- Procedure to analyse edit info (populate user and timestamp) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_edit_info(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_edit_info$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_edit_info (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_row_ids, 1);

    -- Get job details (specifically user_id)
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'edit_info';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] edit_info step not found in snapshot', p_job_id;
    END IF;

    -- Single-pass update to populate audit info and advance priority for all rows.
    -- State is only advanced for non-skipped rows.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            edit_by_user_id = %2$L,
            edit_at = statement_timestamp(),
            edit_comment = %3$L, -- Set edit_comment from job's default
            last_completed_priority = %4$L,
            state = CASE
                        WHEN dt.action = 'skip' THEN dt.state -- Keep existing state if skipped
                        ELSE 'analysing'::public.import_data_state -- Set to analysing for non-skipped
                    END
        WHERE dt.row_id = ANY($1);
    $$, v_data_table_name /* %1$I */, v_job.user_id /* %2$L */, v_job.edit_comment /* %3$L */, v_step.priority /* %4$L */);
    RAISE DEBUG '[Job %] analyse_edit_info: Updating all rows in batch: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_edit_info: Processed % rows in single pass.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_edit_info (Batch): Finished analysis for batch.', p_job_id;
END;
$analyse_edit_info$;


COMMIT;
