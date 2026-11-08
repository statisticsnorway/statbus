```sql
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch_after()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_task worker.tasks;
    v_job public.import_job;
    v_error jsonb;
BEGIN
    -- The worker calls this after publishing its task result. Completion time identifies the
    -- invocation just handled, including when older queued task IDs execute after newer ones.
    SELECT * INTO v_task FROM worker.tasks
    WHERE command = 'import_job_process_batch' AND worker_pid = pg_backend_pid()
    ORDER BY process_stop_at DESC NULLS LAST, id DESC LIMIT 1;
    IF NOT FOUND OR v_task.state <> 'failed' THEN
        RETURN;
    END IF;
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = (v_task.payload->>'job_id')::integer;
    PERFORM admin.set_import_job_user_context(v_job.id);
    v_error := jsonb_build_object('processing_task_failed', v_task.id, 'error', v_task.error);
    EXECUTE format($SQL$
        UPDATE public.%1$I
        SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || $1
        WHERE batch_seq = $2 AND state = 'processing'
    $SQL$, v_job.data_table_name)
    USING v_error, (v_task.payload->>'batch_seq')::integer;
    UPDATE public.import_job
    SET state = 'failed', error = COALESCE(error, v_error::text)
    WHERE id = v_job.id AND (state <> 'failed' OR error IS NULL);
END;
$procedure$
```
