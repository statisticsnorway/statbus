```sql
CREATE OR REPLACE PROCEDURE admin.analyse_valid_time_from_context(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign from the record

    -- Find the target details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'valid_time_from_context';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time_from_context target not found', p_job_id;
    END IF;

    -- Step 1: Batch Update computed_valid_from/to from job defaults
    v_sql := format('
        UPDATE public.%I dt SET
            computed_valid_from = %L::DATE,
            computed_valid_to = %L::DATE,
            last_completed_priority = %L,
            error = NULL, -- Clear any previous errors if needed
            state = %L
        WHERE dt.ctid = ANY(%L);
    ', v_data_table_name, v_job.default_valid_from, v_job.default_valid_to, v_step.priority, 'analysing', p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Updating computed dates: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_valid_time_from_context: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_valid_time_from_context (Batch): Finished analysis for batch.', p_job_id;
END;
$procedure$
```
