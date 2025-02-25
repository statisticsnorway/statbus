-- Down Migration 20250213100637: create worker
BEGIN;

-- Drop triggers using teardown procedure
CALL worker.teardown();

-- Drop trigger functions
DROP FUNCTION worker.notify_worker_about_changes() CASCADE;
DROP FUNCTION worker.notify_worker_about_deletes() CASCADE;

-- Drop command functions
DROP FUNCTION worker.command_refresh_derived_data(jsonb);
DROP FUNCTION worker.command_check_table(jsonb);
DROP FUNCTION worker.command_deleted_row(jsonb);

-- Drop utility functions
DROP FUNCTION worker.statistical_unit_refresh_for_ids(int[], int[], int[], date, date);
DROP FUNCTION worker.notify(jsonb);
DROP FUNCTION worker.process_batch(integer);
DROP FUNCTION worker.process_single(jsonb);
DROP FUNCTION worker.deduplicate_batch();

-- Drop notifications table
REVOKE SELECT, INSERT, UPDATE, DELETE ON worker.notifications FROM authenticated;
REVOKE USAGE, SELECT ON SEQUENCE worker.notifications_id_seq FROM authenticated;
DROP TABLE worker.notifications;

-- Drop last_processed table
REVOKE SELECT, INSERT, UPDATE ON worker.last_processed FROM authenticated;
DROP TABLE worker.last_processed;

-- Drop procedures
DROP PROCEDURE worker.setup();
DROP PROCEDURE worker.teardown();

-- Drop mode function and related objects
DROP FUNCTION worker.mode(worker.mode_type, boolean);
REVOKE SELECT ON worker.settings FROM authenticated;
DROP TABLE worker.settings;
DROP TYPE worker.mode_type;

-- Revoke permissions
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA worker FROM authenticated;
REVOKE USAGE ON SCHEMA worker FROM authenticated;

-- Finally drop the schema
DROP SCHEMA IF EXISTS worker;

END;
