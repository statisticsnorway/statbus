```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN p_batch_seq integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] Processing batch_seq % through all process steps.', job.id, p_batch_seq;
    targets := job.definition_snapshot->'import_step_list';

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        -- Skip holistic steps: they run once after all batches, not per-batch.
        IF COALESCE(target_rec.is_holistic, false) THEN
            CONTINUE;
        END IF;

        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;

        -- Since this is one transaction, any error will roll back the entire batch.
        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, p_batch_seq, target_rec.code;
    END LOOP;

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$
```
