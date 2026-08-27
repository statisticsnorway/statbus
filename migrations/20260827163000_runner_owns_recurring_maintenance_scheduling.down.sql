BEGIN;

-- Restores the pre-STATBUS-263 handler, self-reschedule included.
CREATE OR REPLACE PROCEDURE worker.command_import_job_cleanup(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
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
        END;
    END LOOP;

    RAISE DEBUG 'Finished worker.command_import_job_cleanup. Deleted % expired jobs.', v_deleted_count;

    PERFORM worker.enqueue_import_job_cleanup();
END;
$procedure$;

DROP FUNCTION IF EXISTS worker.seed_recurring_tasks();
DROP FUNCTION IF EXISTS worker.schedule_recurring_after(timestamptz);
DROP FUNCTION IF EXISTS worker.ensure_recurring_task(text, jsonb);
ALTER TABLE worker.command_registry DROP COLUMN schedule_interval;

END;
