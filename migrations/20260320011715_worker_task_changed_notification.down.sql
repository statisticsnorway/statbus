-- Down Migration 20260320011715: worker_task_changed_notification
BEGIN;

DROP TRIGGER IF EXISTS trg_notify_task_changed ON worker.tasks;
DROP FUNCTION IF EXISTS worker.notify_task_changed();

END;
