-- Migration 20260306154720: make_pipeline_progress_logged
BEGIN;

ALTER TABLE worker.pipeline_progress SET LOGGED;
COMMENT ON TABLE worker.pipeline_progress IS
  'Tracks progress of analytics pipeline steps for UI display.
   LOGGED: survives crashes so UI shows progress after recovery.
   Write volume is low (one update per child task completion).';

END;
