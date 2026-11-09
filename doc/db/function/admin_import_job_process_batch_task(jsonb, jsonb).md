```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch_task(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_rows_processed integer;
    v_batch_seq integer := (payload->>'batch_seq')::integer;
BEGIN
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = (payload->>'job_id')::integer;
    IF v_batch_seq IS NULL OR v_batch_seq < 1 THEN
        RAISE EXCEPTION 'A positive import processing batch_seq is required';
    END IF;
    PERFORM admin.set_import_job_user_context(v_job.id);
    IF v_job.state <> 'processing_data' THEN
        p_info := jsonb_build_object('job_state', v_job.state::text);
        RETURN;
    END IF;
    v_rows_processed := admin.import_job_process_one_batch(v_job, v_batch_seq);
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = v_job.id;
    IF v_rows_processed IS NULL OR v_job.state = 'failed' THEN
        -- The worker records a failed leaf after rolling back this handler. Its after_procedure
        -- publishes the job failure outside that savepoint so parent fan-in also remains failed.
        RAISE EXCEPTION USING MESSAGE = COALESCE(v_job.error, 'Import processing batch failed');
    END IF;
    p_info := jsonb_build_object('batch_rows_imported', v_rows_processed);
END;
$procedure$
```
