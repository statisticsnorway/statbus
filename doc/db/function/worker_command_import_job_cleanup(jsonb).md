```sql
CREATE OR REPLACE PROCEDURE worker.command_import_job_cleanup(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_job_record RECORD;
    v_deleted_count INTEGER := 0;
BEGIN
    RAISE DEBUG 'Running worker.command_import_job_cleanup';

    FOR v_job_record IN
        SELECT id, slug FROM public.import_job WHERE expires_at <= now()
    LOOP
        RAISE DEBUG '[Job % (Slug: %)] Expired, attempting deletion.', v_job_record.id, v_job_record.slug;
        BEGIN
            DELETE FROM public.import_job WHERE id = v_job_record.id;
            v_deleted_count := v_deleted_count + 1;
            RAISE DEBUG '[Job % (Slug: %)] Successfully deleted.', v_job_record.id, v_job_record.slug;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING '[Job % (Slug: %)] Failed to delete expired import job: %', v_job_record.id, v_job_record.slug, SQLERRM;
                -- Optionally, update the job with an error or take other action
                -- For now, we just log and continue, so other jobs can be processed.
        END;
    END LOOP;

    RAISE DEBUG 'Finished worker.command_import_job_cleanup. Deleted % expired jobs.', v_deleted_count;

    -- Schedule to run again in 24 hours
    PERFORM worker.enqueue_import_job_cleanup();
END;
$procedure$
```
