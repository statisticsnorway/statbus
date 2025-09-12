```sql
CREATE OR REPLACE FUNCTION admin.import_job_processing_phase(job import_job)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch_row_ids INTEGER[];
BEGIN
    RAISE DEBUG '[Job %] Processing phase: checking for a batch.', job.id;

    -- This logic ensures that all rows belonging to the same new entity (sharing a founding_row_id) are always processed in the same batch.
    EXECUTE format(
        $$
        WITH entity_batch AS (
            SELECT DISTINCT COALESCE(founding_row_id, row_id) AS entity_root_id
            FROM public.%1$I
            WHERE state = 'processing' AND action = 'use'
            ORDER BY entity_root_id
            LIMIT %2$L
        )
        SELECT array_agg(t.row_id)
        FROM (
            SELECT dt.row_id
            FROM public.%1$I dt
            JOIN entity_batch eb ON COALESCE(dt.founding_row_id, dt.row_id) = eb.entity_root_id
            WHERE dt.state = 'processing' AND dt.action = 'use'
            ORDER BY dt.row_id
            FOR UPDATE SKIP LOCKED
        ) t
        $$,
        job.data_table_name,        /* %1$I */
        job.processing_batch_size   /* %2$L */
    ) INTO v_batch_row_ids;

    IF v_batch_row_ids IS NOT NULL AND array_length(v_batch_row_ids, 1) > 0 THEN
        RAISE DEBUG '[Job %] Found batch of % rows to process.', job.id, array_length(v_batch_row_ids, 1);
        BEGIN
            CALL admin.import_job_process_batch(job, v_batch_row_ids);

            EXECUTE format($$UPDATE public.%1$I SET state = 'processed' WHERE row_id = ANY($1)$$,
                           job.data_table_name /* %1$I */) USING v_batch_row_ids;
            RAISE DEBUG '[Job %] Batch successfully processed. Marked % rows as processed.', job.id, array_length(v_batch_row_ids, 1);
        EXCEPTION WHEN OTHERS THEN
            DECLARE
                error_message TEXT;
                error_context TEXT;
            BEGIN
                GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                                      error_context = PG_EXCEPTION_CONTEXT;
                RAISE WARNING '[Job %] Error processing batch: %. Context: %. Marking batch rows as error and failing job.', job.id, error_message, error_context;
                EXECUTE format($$UPDATE public.%1$I SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || %2$L WHERE row_id = ANY($1)$$,
                               job.data_table_name /* %1$I */, jsonb_build_object('process_batch_error', error_message, 'context', error_context) /* %2$L */) USING v_batch_row_ids;
                UPDATE public.import_job SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context), state = 'finished' WHERE id = job.id;
                -- On error, do not reschedule.
                RETURN FALSE;
            END;
        END;
        RETURN TRUE; -- Work was done.
    ELSE
        RAISE DEBUG '[Job %] No more rows found in ''processing'' state. Phase complete.', job.id;
        RETURN FALSE; -- No work found.
    END IF;
END;
$function$
```
