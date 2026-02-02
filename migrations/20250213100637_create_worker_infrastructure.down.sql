-- Down Migration 20250213100637: create worker infrastructure
BEGIN;

-- Drop triggers created by setup() on public tables
CALL worker.teardown();

-- Drop trigger on command_registry
DROP TRIGGER IF EXISTS command_registry_queue_change_trigger ON worker.command_registry;

-- Drop trigger functions
DROP FUNCTION IF EXISTS worker.notify_worker_about_changes() CASCADE;
DROP FUNCTION IF EXISTS worker.notify_worker_about_deletes() CASCADE;
DROP FUNCTION IF EXISTS worker.notify_worker_queue_change() CASCADE;

-- Drop task enqueue functions
DROP FUNCTION IF EXISTS worker.enqueue_check_table(TEXT, INTEGER);
DROP FUNCTION IF EXISTS worker.enqueue_deleted_row(TEXT, INT, INT, INT, DATE, DATE);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date);
DROP FUNCTION IF EXISTS worker.enqueue_derive_reports(DATE, DATE);
DROP FUNCTION IF EXISTS worker.enqueue_task_cleanup(INT, INT);

-- Drop command handler procedures (payload versions)
DROP PROCEDURE IF EXISTS worker.command_check_table(JSONB);
DROP PROCEDURE IF EXISTS worker.command_deleted_row(JSONB);
DROP PROCEDURE IF EXISTS worker.derive_statistical_unit(JSONB); -- Note: Name corrected based on up.sql intent
DROP PROCEDURE IF EXISTS worker.derive_reports(JSONB);
DROP PROCEDURE IF EXISTS worker.command_task_cleanup(JSONB);

-- Drop core logic functions (non-payload versions)
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date);
DROP FUNCTION IF EXISTS worker.derive_reports(DATE, DATE);
DROP PROCEDURE IF EXISTS worker.notify_check_is_deriving_statistical_units();
DROP PROCEDURE IF EXISTS worker.notify_check_is_deriving_reports();

-- Drop utility functions/procedures
DROP FUNCTION IF EXISTS worker.reset_abandoned_processing_tasks();
DROP PROCEDURE IF EXISTS worker.process_tasks(INT, INT, TEXT, BIGINT);

-- Drop structured concurrency functions
DROP TRIGGER IF EXISTS tasks_enforce_no_grandchildren ON worker.tasks;
DROP FUNCTION IF EXISTS worker.enforce_no_grandchildren();
DROP FUNCTION IF EXISTS worker.complete_parent_if_ready(BIGINT);
DROP FUNCTION IF EXISTS worker.has_failed_siblings(BIGINT);
DROP FUNCTION IF EXISTS worker.has_pending_children(BIGINT);
DROP FUNCTION IF EXISTS worker.spawn(TEXT, JSONB, BIGINT, BIGINT);

-- Revoke permissions before dropping tables/sequences
REVOKE SELECT, INSERT, UPDATE, DELETE ON worker.tasks FROM authenticated;
REVOKE USAGE, SELECT ON SEQUENCE worker.tasks_id_seq FROM authenticated;
REVOKE SELECT ON worker.command_registry FROM authenticated;
REVOKE SELECT ON worker.last_processed FROM authenticated;

-- Drop tables (order matters due to foreign keys)
DROP TABLE IF EXISTS worker.tasks; -- Depends on command_registry
DROP TABLE IF EXISTS worker.command_registry; -- Depends on queue_registry
DROP TABLE IF EXISTS worker.queue_registry;
DROP TABLE IF EXISTS worker.last_processed;

-- Drop setup/teardown procedures
DROP PROCEDURE IF EXISTS worker.setup();
DROP PROCEDURE IF EXISTS worker.teardown();

-- Drop sequence used by tasks table
DROP SEQUENCE IF EXISTS public.worker_task_priority_seq;

-- Revoke schema-level permissions
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA worker FROM authenticated; -- Best effort, CASCADE might handle this
REVOKE USAGE ON SCHEMA worker FROM authenticated;

-- Drop the task_state type
DROP TYPE IF EXISTS worker.task_state;

-- Finally drop the schema itself, CASCADE handles remaining objects within the schema
DROP SCHEMA IF EXISTS worker CASCADE;

END;
