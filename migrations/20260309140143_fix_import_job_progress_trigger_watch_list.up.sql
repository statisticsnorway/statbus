BEGIN;

-- The progress update trigger computes analysis_rows_per_sec and import_rows_per_sec
-- using analysis_stop_at and processing_stop_at. But those timestamps are set by
-- the state_change_before trigger (which watches state), not the progress trigger.
-- Since the triggers fire on different UPDATE statements, the progress trigger
-- never sees the stop timestamps for small/fast jobs.
--
-- Fix: add analysis_stop_at and processing_stop_at to the progress trigger's watch list.
DROP TRIGGER IF EXISTS import_job_progress_update_trigger ON public.import_job;
CREATE TRIGGER import_job_progress_update_trigger
    BEFORE UPDATE OF imported_rows, completed_analysis_steps_weighted, error_count, analysis_stop_at, processing_stop_at
    ON public.import_job
    FOR EACH ROW
    EXECUTE FUNCTION admin.import_job_progress_update();

END;
