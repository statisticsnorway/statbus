```sql
CREATE OR REPLACE FUNCTION admin.import_job_process_one_batch(job import_job, p_batch_seq integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows_processed integer;
    error_message text;
    error_context text;
BEGIN
    -- The task uniqueness index gives each (job, batch) one scheduled leaf. This lock also makes a
    -- direct replay wait for an in-flight invocation before checking its committed row states.
    PERFORM pg_advisory_xact_lock(hashtextextended(format('import_batch:%s:%s', job.id, p_batch_seq), 0));
    EXECUTE format($SQL$
        SELECT count(*) FROM public.%1$I WHERE batch_seq = $1 AND state = 'processing'
    $SQL$, job.data_table_name) INTO v_rows_processed USING p_batch_seq;
    IF v_rows_processed = 0 THEN
        RETURN 0;
    END IF;

    BEGIN
        CALL admin.import_job_process_batch(job, p_batch_seq);
        EXECUTE format($SQL$
            UPDATE public.%1$I SET state = 'processed'
            WHERE batch_seq = $1 AND state = 'processing'
        $SQL$, job.data_table_name) USING p_batch_seq;
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
        -- Keep this atomic increment at the transaction tail so progress remains live without
        -- holding the shared job row throughout temporal_merge or its supporting queries.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;
    EXCEPTION
        WHEN deadlock_detected OR serialization_failure THEN
            RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT, error_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
                job.id, p_batch_seq, error_message, error_context;
            EXECUTE format($SQL$
                UPDATE public.%1$I
                SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || $1
                WHERE batch_seq = $2
            $SQL$, job.data_table_name)
            USING jsonb_build_object('process_batch_error', error_message, 'context', error_context), p_batch_seq;
            UPDATE public.import_job
            SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::text,
                state = 'failed'
            WHERE id = job.id;
            RETURN NULL;
    END;
    RETURN v_rows_processed;
END;
$function$
```
