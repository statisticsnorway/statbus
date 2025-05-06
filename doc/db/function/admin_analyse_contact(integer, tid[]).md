```sql
CREATE OR REPLACE PROCEDURE admin.analyse_contact(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$ -- Function name remains the same, step name changed
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_contact (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'contact'; -- Use new step name
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found', p_job_id;
    END IF;

    -- Step 1: Batch Update Success Rows (No specific analysis needed for contact fields, just advance priority)
    -- No error checking needed for this simple step unless validation is added.
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear any previous errors if needed
            state = %L
        WHERE dt.ctid = ANY(%L);
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_contact: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_contact: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_contact (Batch): Finished analysis for batch.', p_job_id;
END;
$procedure$
```
