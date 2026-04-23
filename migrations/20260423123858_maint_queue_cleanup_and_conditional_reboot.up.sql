-- Migration 20260423123858: maint_queue_cleanup_and_conditional_reboot
--
-- Forward correction for 20260422161000_maint_queue_migration (shipped in
-- rc.53 as an unconditional enqueue). That migration's correct shape is
-- conditional — enqueue only where stuck — but the file is immutable once
-- a release tagged it, so the correction ships here.
--
-- Two jobs:
--   1. Clean up the pending task_cleanup / import_job_cleanup rows rc.53's
--      body A inserted on stuck sites (where the canonical seed rows from
--      20250213100637 had flipped to state='failed' from an older schema
--      mismatch, the pending-partial-unique index did NOT match, and
--      enqueue_X() therefore inserted a NEW pending row at a fresh id
--      alongside the failed predecessor).
--   2. Apply the conditional reboot (enqueue ONLY where a failed row
--      exists AND no pending successor) as a self-healing hook going
--      forward.
--
-- Net effect matrix:
--   - Fresh test/dev DB (ids 1,2 pending from worker.setup(), no failed):
--       step 1 no-op (guard requires a matching failed row), step 2 no-op
--       (no failed rows). End state: ids 1,2 pending. Tests see a clean
--       DB without any DELETE compensation in setup.sql / 116 / 121 / 122.
--   - Healthy rc.53 cloud site (no failed rows):
--       both steps no-op.
--   - Stuck rc.53 cloud site (ids 1,2 failed + body-A pending at later id):
--       step 1 removes the body-A pending row; step 2 re-enqueues through
--       the canonical path. End: failed predecessor preserved + fresh
--       pending via enqueue_X().
--   - Pre-rc.53 stuck site jumping to rc.54: rc.53 body A runs first
--       (inserts fresh pending alongside failed), then this migration
--       cleans up and canonicalises via step 1 + step 2.
--
-- Down: no-op. Reversing the cleanup would re-introduce the "pending
-- alongside failed" shape the forward migration is correcting.

BEGIN;

-- Step 1: remove body-A pending rows on stuck sites so step 2 can
-- canonicalise via enqueue_X(). Scoped to maintenance commands only and
-- guarded on "failed row exists for the same command" so fresh installs
-- and healthy sites are untouched.
DELETE FROM worker.tasks
WHERE command IN ('task_cleanup', 'import_job_cleanup')
  AND state = 'pending'::worker.task_state
  AND EXISTS (
    SELECT 1
    FROM worker.tasks AS stuck_failed
    WHERE stuck_failed.command = worker.tasks.command
      AND stuck_failed.state = 'failed'::worker.task_state
  );

-- Step 2: conditional reboot. Enqueue only where a failed row still
-- exists AND no pending successor remains after step 1. On fresh DBs and
-- healthy sites this entire block is a no-op.
DO $maint_queue_reboot$
DECLARE
    v_rebooted text[] := ARRAY[]::text[];
BEGIN
    IF EXISTS (SELECT 1 FROM worker.tasks
                WHERE command = 'task_cleanup'
                  AND state = 'failed'::worker.task_state)
       AND NOT EXISTS (SELECT 1 FROM worker.tasks
                        WHERE command = 'task_cleanup'
                          AND state = 'pending'::worker.task_state)
    THEN
        PERFORM worker.enqueue_task_cleanup();
        v_rebooted := array_append(v_rebooted, 'task_cleanup');
    END IF;

    IF EXISTS (SELECT 1 FROM worker.tasks
                WHERE command = 'import_job_cleanup'
                  AND state = 'failed'::worker.task_state)
       AND NOT EXISTS (SELECT 1 FROM worker.tasks
                        WHERE command = 'import_job_cleanup'
                          AND state = 'pending'::worker.task_state)
    THEN
        PERFORM worker.enqueue_import_job_cleanup();
        v_rebooted := array_append(v_rebooted, 'import_job_cleanup');
    END IF;

    IF array_length(v_rebooted, 1) IS NOT NULL THEN
        RAISE NOTICE 'maint_queue_cleanup_and_conditional_reboot: rebooted stuck commands: %', v_rebooted;
    ELSE
        RAISE NOTICE 'maint_queue_cleanup_and_conditional_reboot: no stuck state — no-op.';
    END IF;
END;
$maint_queue_reboot$;

COMMIT;
