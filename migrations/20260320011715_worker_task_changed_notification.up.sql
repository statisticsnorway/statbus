-- Migration 20260320011715: worker_task_changed_notification
-- Add a lightweight pg_notify trigger on worker.tasks state changes
-- so the frontend can replace 5-second polling with event-driven updates.
BEGIN;

CREATE FUNCTION worker.notify_task_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = worker, pg_temp
AS $notify_task_changed$
BEGIN
    -- Only notify on actual state changes, not every UPDATE
    IF OLD.state IS DISTINCT FROM NEW.state THEN
        PERFORM pg_notify('worker_task_changed',
            json_build_object(
                'id', NEW.id,
                'parent_id', NEW.parent_id
            )::text
        );
    END IF;
    RETURN NEW;
END;
$notify_task_changed$;

COMMENT ON FUNCTION worker.notify_task_changed IS
'Lightweight trigger: sends pg_notify on task state changes so the admin UI
can replace polling with event-driven updates. Payload includes id and parent_id
so clients can filter to relevant changes. Debounced at 1s per parent_id in
the SSE layer.';

CREATE TRIGGER trg_notify_task_changed
    AFTER UPDATE ON worker.tasks
    FOR EACH ROW
    EXECUTE FUNCTION worker.notify_task_changed();

END;
