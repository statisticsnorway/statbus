```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN batch_row_id_ranges int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
    v_should_disable_triggers BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] Processing batch with ranges %s through all process steps.', job.id, batch_row_id_ranges::text;
    targets := job.definition_snapshot->'import_step_list';

    -- Check if the batch contains any operations that are not simple inserts.
    -- If so, we need to disable FK triggers to allow for temporary inconsistencies.
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM public.%I WHERE row_id <@ $1 AND operation IS DISTINCT FROM %L)',
        job.data_table_name,
        'insert'
    )
    INTO v_should_disable_triggers
    USING batch_row_id_ranges;

    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Batch contains updates/replaces. Disabling FK triggers.', job.id;
        CALL admin.disable_temporal_triggers();
    ELSE
        RAISE DEBUG '[Job %] Batch is insert-only. Skipping trigger disable/enable.', job.id;
    END IF;

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;

        -- Since this is one transaction, any error will roll back the entire batch.
        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, batch_row_id_ranges, target_rec.code;
    END LOOP;

    -- Re-enable triggers if they were disabled.
    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Re-enabling FK triggers.', job.id;
        CALL admin.enable_temporal_triggers();
    END IF;

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$
```
