```sql
CREATE OR REPLACE PROCEDURE import.analyse_contact(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_contact (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'contact';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found in snapshot', p_job_id;
    END IF;

    -- This procedure now copies raw contact fields to their typed internal counterparts
    -- and advances the priority for all processed rows. The lookup for existing
    -- contact_id has been removed, as the natural key lookup will be handled
    -- by the process_contact step.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            web_address = NULLIF(dt.web_address_raw, ''),
            email_address = NULLIF(dt.email_address_raw, ''),
            phone_number = NULLIF(dt.phone_number_raw, ''),
            landline = NULLIF(dt.landline_raw, ''),
            mobile_number = NULLIF(dt.mobile_number_raw, ''),
            fax_number = NULLIF(dt.fax_number_raw, ''),
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$,
        v_data_table_name,    /* %1$I */
        v_step.priority       /* %2$L */
    );

    RAISE DEBUG '[Job %] analyse_contact: Updating rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_contact: Processed % rows in single pass.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_contact: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_contact_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_contact: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    RAISE DEBUG '[Job %] analyse_contact (Batch): Finished analysis for batch. Processed % rows.', p_job_id, v_update_count;
END;
$procedure$
```
