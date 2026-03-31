\echo "=== Worker maintenance cleanup functions ==="
\echo "Verify that cleanup and enqueue functions execute without errors."
\echo "Any column mismatch (e.g. stale processed_at) causes immediate failure."

BEGIN;

-- Clear any pre-existing maintenance tasks for deterministic output
DELETE FROM worker.tasks WHERE command IN ('task_cleanup', 'import_job_cleanup');

\echo "--- command_task_cleanup: executes DELETE on process_start_at column ---"
CALL worker.command_task_cleanup('{}'::jsonb);

\echo "--- enqueue_task_cleanup: references process_start_at in ON CONFLICT ---"
SELECT worker.enqueue_task_cleanup() IS NOT NULL AS enqueued;

\echo "--- enqueue_import_job_cleanup: references process_start_at in ON CONFLICT ---"
SELECT worker.enqueue_import_job_cleanup() IS NOT NULL AS enqueued;

\echo "--- Verify maintenance tasks were created with correct state ---"
SELECT command, state
FROM worker.tasks
WHERE command IN ('task_cleanup', 'import_job_cleanup')
ORDER BY command;

ROLLBACK;
