```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Check if any Phase 1 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 1 tasks that still need to run.
  -- Exclude collect_changes: it always has a pending task queued via dedup index
  -- as the entry-point trigger — it's not actual derive work.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_statistical_units'
    AND t.command <> 'collect_changes'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 1 work pending, don't stop yet
  END IF;

  -- If collect_changes is pending, more Phase 1 work is guaranteed
  -- (collect_changes always leads to derive_statistical_unit), so stay active.
  -- Reset to collect_changes step with cleared counts — the previous cycle's
  -- counts are stale and the new collect_changes will set fresh ones.
  IF EXISTS (
    SELECT 1 FROM worker.tasks
    WHERE command = 'collect_changes'
    AND state = 'pending'
  ) THEN
    UPDATE worker.pipeline_progress
    SET step = 'collect_changes', total = 0, completed = 0,
        affected_establishment_count = NULL,
        affected_legal_unit_count = NULL,
        affected_enterprise_count = NULL,
        affected_power_group_count = NULL,
        updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    RETURN;
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$procedure$
```
