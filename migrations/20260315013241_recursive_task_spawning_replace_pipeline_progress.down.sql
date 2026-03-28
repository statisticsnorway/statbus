-- Down Migration: recursive_task_spawning_replace_pipeline_progress
-- This is a destructive rollback. Run recreate-database instead.
BEGIN;

DO $$ BEGIN
  RAISE EXCEPTION 'This migration cannot be rolled back automatically. Use ./dev.sh recreate-database instead.';
END $$;

END;
