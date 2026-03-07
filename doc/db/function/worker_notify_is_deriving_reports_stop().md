```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Check if any Phase 2 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 2 tasks that still need to run.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_reports'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 2 work pending, don't stop yet
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_reports';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_reports', 'status', false)::text
  );
END;
$procedure$
```
