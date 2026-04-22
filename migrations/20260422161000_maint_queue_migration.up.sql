BEGIN;

-- Re-enqueue stuck maintenance commands, but ONLY where they are stuck.
-- Guard: a command is "stuck" when a failed row exists AND there is no
-- pending successor. This matches the real production class observed on
-- installed sites (statbus_et, rune, etc. — task_cleanup / import_job_cleanup
-- at state='failed' from an old schema mismatch, no pending row because
-- the self-re-enqueue-on-success loop broke when the failed row landed).
--
-- Consequence: on any DB without that stuck state — fresh test DBs, fresh
-- dev DBs, installed sites that already recovered manually — this migration
-- is a no-op. No rows inserted, no sequence advanced, no test fixtures
-- perturbed.
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
        RAISE NOTICE 'maint-queue-migration: re-enqueued stuck commands: %', v_rebooted;
    ELSE
        RAISE NOTICE 'maint-queue-migration: no stuck maintenance state — no-op.';
    END IF;
END;
$maint_queue_reboot$;

COMMIT;
