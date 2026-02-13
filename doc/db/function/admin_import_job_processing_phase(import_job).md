```sql
CREATE OR REPLACE FUNCTION admin.import_job_processing_phase(job import_job)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_batch INTEGER;
    v_max_batch INTEGER;
    v_rows_processed INTEGER;
    error_message TEXT;
    error_context TEXT;
BEGIN
    -- Get the current batch to process (smallest batch_seq that still has unprocessed rows)
    EXECUTE format($$
        SELECT MIN(batch_seq), MAX(batch_seq)
        FROM public.%1$I
        WHERE batch_seq IS NOT NULL AND state = 'processing'
    $$, job.data_table_name) INTO v_current_batch, v_max_batch;

    IF v_current_batch IS NULL THEN
        RAISE DEBUG '[Job %] No more batches to process. Phase complete.', job.id;
        RETURN FALSE; -- No work found.
    END IF;

    RAISE DEBUG '[Job %] Processing batch % of % (max).', job.id, v_current_batch, v_max_batch;

    BEGIN
        CALL admin.import_job_process_batch(job, v_current_batch);

        -- Mark all rows in the batch that are not in an error state as 'processed'.
        EXECUTE format($$
            UPDATE public.%1$I 
            SET state = 'processed' 
            WHERE batch_seq = %2$L AND state != 'error'
        $$, job.data_table_name, v_current_batch);
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
        
        RAISE DEBUG '[Job %] Batch % successfully processed. Marked % non-error rows as processed.', 
            job.id, v_current_batch, v_rows_processed;

        -- Increment imported_rows counter directly instead of doing a full table scan.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                              error_context = PG_EXCEPTION_CONTEXT;
        RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.', 
            job.id, v_current_batch, error_message, error_context;
        
        EXECUTE format($$
            UPDATE public.%1$I 
            SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || %2$L 
            WHERE batch_seq = %3$L
        $$, job.data_table_name, 
            jsonb_build_object('process_batch_error', error_message, 'context', error_context),
            v_current_batch);
        
        UPDATE public.import_job 
        SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::TEXT, 
            state = 'failed' 
        WHERE id = job.id;
        
        RETURN FALSE; -- On error, do not reschedule.
    END;
    
    RETURN TRUE; -- Work was done.
END;
$function$
```
