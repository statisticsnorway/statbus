-- Down Migration 20260306154720: make_pipeline_progress_logged
BEGIN;

ALTER TABLE worker.pipeline_progress SET UNLOGGED;
COMMENT ON TABLE worker.pipeline_progress IS
  'Tracks progress of analytics pipeline steps for UI display.
   UNLOGGED: progress is ephemeral — survives clean restarts via shutdown hook,
   but resets on crash (which is fine, progress resets on crash anyway).';

END;
