```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN batch_row_ids integer[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] Processing batch of % rows through all process steps.', job.id, array_length(batch_row_ids, 1);
    targets := job.definition_snapshot->'import_step_list';

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;
        
        -- Since this is one transaction, any error will roll back the entire batch.
        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, batch_row_ids, target_rec.code;
    END LOOP;
    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$
```
