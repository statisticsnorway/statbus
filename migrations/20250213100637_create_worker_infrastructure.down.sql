-- Down Migration 20250213100637: create worker
BEGIN;
-- Drop triggers using teardown procedure
CALL worker.teardown();

-- Drop trigger functions
DROP FUNCTION IF EXISTS worker.notify_worker_about_changes() CASCADE;
DROP FUNCTION IF EXISTS worker.notify_worker_about_deletes() CASCADE;
DROP FUNCTION IF EXISTS worker.notify_worker_queue_change() CASCADE;

-- Drop task enqueue functions
DROP FUNCTION IF EXISTS worker.enqueue_check_table(TEXT, BIGINT);
DROP FUNCTION IF EXISTS worker.enqueue_deleted_row(TEXT, INT, INT, INT, DATE, DATE);
DROP FUNCTION IF EXISTS worker.enqueue_derive_data(INT[], INT[], INT[], DATE, DATE);
DROP FUNCTION IF EXISTS worker.enqueue_task_cleanup(INT, INT);

-- Drop command procedures
DROP PROCEDURE IF EXISTS worker.derive_data(JSONB);
DROP PROCEDURE IF EXISTS worker.command_check_table(JSONB);
DROP PROCEDURE IF EXISTS worker.command_deleted_row(JSONB);
DROP PROCEDURE IF EXISTS worker.command_task_cleanup(JSONB);

-- Drop utility functions
DROP FUNCTION IF EXISTS worker.derive_data(INT[], INT[], INT[], DATE, DATE);
DROP FUNCTION IF EXISTS worker.reset_abandoned_processing_tasks();
DROP PROCEDURE IF EXISTS worker.process_tasks(INT, INT, TEXT);

-- Drop tasks table
REVOKE SELECT, INSERT, UPDATE, DELETE ON worker.tasks FROM authenticated;
REVOKE USAGE, SELECT ON SEQUENCE worker.tasks_id_seq FROM authenticated;
DROP TABLE IF EXISTS worker.tasks;

-- Drop command registry table
DROP TABLE IF EXISTS worker.command_registry;

-- Drop queue registry table
DROP TABLE IF EXISTS worker.queue_registry;

-- Drop last_processed table
REVOKE SELECT ON worker.last_processed FROM authenticated;
DROP TABLE IF EXISTS worker.last_processed;

-- Drop procedures
DROP PROCEDURE IF EXISTS worker.setup();
DROP PROCEDURE IF EXISTS worker.teardown();

-- Drop sequence
DROP SEQUENCE IF EXISTS public.worker_task_priority_seq;

-- Revoke permissions
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA worker FROM authenticated;
REVOKE USAGE ON SCHEMA worker FROM authenticated;

-- Drop the task_state type
DROP TYPE IF EXISTS worker.task_state;

-- Finally drop the schema
DROP SCHEMA IF EXISTS worker;

END;
