BEGIN;

-- Restore original trigger without analysis_stop_at and processing_stop_at
DROP TRIGGER IF EXISTS import_job_progress_update_trigger ON public.import_job;
CREATE TRIGGER import_job_progress_update_trigger
    BEFORE UPDATE OF imported_rows, completed_analysis_steps_weighted, error_count
    ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_progress_update();

END;
