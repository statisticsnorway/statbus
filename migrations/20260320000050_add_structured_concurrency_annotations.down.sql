-- Down Migration 20260320000050: add_structured_concurrency_annotations
-- Remove annotations (comments are metadata-only, no schema impact)
BEGIN;

COMMENT ON TYPE worker.child_mode IS NULL;
COMMENT ON COLUMN worker.tasks.child_mode IS NULL;
COMMENT ON COLUMN worker.tasks.depth IS NULL;
COMMENT ON COLUMN worker.tasks.info IS NULL;
COMMENT ON COLUMN worker.tasks.process_stop_at IS NULL;
COMMENT ON COLUMN worker.tasks.process_duration_ms IS NULL;
COMMENT ON COLUMN worker.tasks.completion_duration_ms IS NULL;
COMMENT ON FUNCTION worker.spawn IS NULL;
COMMENT ON PROCEDURE worker.process_tasks IS NULL;
COMMENT ON FUNCTION worker.complete_parent_if_ready IS NULL;
COMMENT ON FUNCTION worker.notify_task_progress IS NULL;
COMMENT ON FUNCTION worker.rescue_stuck_waiting_parent IS NULL;

END;
