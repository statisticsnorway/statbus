-- Down Migration: recursive_task_spawning_replace_pipeline_progress
-- This is a destructive rollback. Run recreate-database instead.
BEGIN;

RAISE EXCEPTION 'This migration cannot be rolled back automatically. Use ./devops/manage-statbus.sh recreate-database instead.';

END;
