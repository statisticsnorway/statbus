-- Down Migration 20250213100637: create worker
BEGIN;
-- Drop triggers using teardown procedure
CALL worker.teardown();

-- Drop trigger functions
DROP FUNCTION worker.notify_worker_about_changes() CASCADE;
DROP FUNCTION worker.notify_worker_about_deletes() CASCADE;
DROP FUNCTION worker.notify_worker_queue_change() CASCADE;

-- Drop task enqueue functions
DROP FUNCTION worker.enqueue_check_table(TEXT, BIGINT);
DROP FUNCTION worker.enqueue_deleted_row(TEXT, INT, INT, INT, DATE, DATE);
DROP FUNCTION worker.enqueue_refresh_derived_data(DATE, DATE);
DROP FUNCTION worker.enqueue_task_cleanup(INT, INT);

-- Drop command functions
DROP FUNCTION worker.command_refresh_derived_data(JSONB);
DROP FUNCTION worker.command_check_table(JSONB);
DROP FUNCTION worker.command_deleted_row(JSONB);
DROP FUNCTION worker.command_task_cleanup(JSONB);

-- Drop utility functions
DROP FUNCTION worker.statistical_unit_refresh_for_ids(int[], int[], int[], date, date);
DROP FUNCTION worker.process_tasks(INT, INT, TEXT);

-- Drop tasks table
REVOKE SELECT, INSERT, UPDATE, DELETE ON worker.tasks FROM authenticated;
REVOKE USAGE, SELECT ON SEQUENCE worker.tasks_id_seq FROM authenticated;
DROP TABLE worker.tasks;

-- Drop command registry table
DROP TABLE worker.command_registry;

-- Drop queue registry table
DROP TABLE worker.queue_registry;

-- Drop last_processed table
REVOKE SELECT ON worker.last_processed FROM authenticated;
DROP TABLE worker.last_processed;

-- Drop procedures
DROP PROCEDURE worker.setup();
DROP PROCEDURE worker.teardown();

-- Revoke permissions
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA worker FROM authenticated;
REVOKE USAGE ON SCHEMA worker FROM authenticated;

-- Drop the task_status type
DROP TYPE worker.task_status;

-- Finally drop the schema
DROP SCHEMA worker;

END;
