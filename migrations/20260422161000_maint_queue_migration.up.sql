BEGIN;

-- Reboot maintenance-queue self-scheduling: failed rows (not covered by the
-- partial unique index on state='pending') never get retried because the
-- command re-enqueues itself only on successful completion. Insert fresh
-- pending rows via the canonical enqueue paths. Idempotent on healthy
-- installs — existing pending rows are merged via ON CONFLICT.
SELECT worker.enqueue_task_cleanup();
SELECT worker.enqueue_import_job_cleanup();

-- Assertion: after this migration, each command MUST have a pending row.
-- If not, the migration silently failed and we want to know immediately.
DO $maint_queue_assert$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM worker.tasks
                 WHERE command = 'task_cleanup'
                   AND state = 'pending'::worker.task_state) THEN
    RAISE EXCEPTION 'maint-queue-migration: no pending task_cleanup row after enqueue';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM worker.tasks
                 WHERE command = 'import_job_cleanup'
                   AND state = 'pending'::worker.task_state) THEN
    RAISE EXCEPTION 'maint-queue-migration: no pending import_job_cleanup row after enqueue';
  END IF;
END;
$maint_queue_assert$;

COMMIT;
