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

    -- Temporarily disable all relevant foreign key triggers for the duration of the batch transaction.
    -- This allows the transaction to reach a temporarily inconsistent state between procedure calls
    -- (e.g., a child record being created before its parent), with the guarantee that the final state
    -- will be consistent when triggers are re-enabled at the end of the transaction.
    CALL admin.disable_temporal_triggers();

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

    -- Re-enable triggers. They will be checked for the entire transaction at this point.
    CALL admin.enable_temporal_triggers();

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$
```
