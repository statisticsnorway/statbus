BEGIN;

-- Fix 1: Include 'preparing_data' in is_importing()
-- The preparing_data state (copying upload → data table) is active work
-- but was missing from the active check and jobs aggregation.
CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state IN ('preparing_data', 'analysing_data', 'processing_data')
    ),
    'jobs', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ij.id,
        'state', ij.state,
        'total_rows', ij.total_rows,
        'imported_rows', ij.imported_rows,
        'analysis_completed_pct', ij.analysis_completed_pct,
        'import_completed_pct', ij.import_completed_pct
      )) FROM public.import_job AS ij
      WHERE ij.state IN ('preparing_data', 'analysing_data', 'processing_data')),
      '[]'::jsonb
    )
  );
$function$;

-- Fix 2: Exclude collect_changes from Phase 1 stop guard
-- collect_changes always has a pending task (dedup index entry-point pattern),
-- so the guard never fires and the Phase 1 progress row persists forever at 100%.
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_statistical_units_stop$
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
  -- Reset to collect_changes step with unknown counts (not yet collected).
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
$notify_is_deriving_statistical_units_stop$;

-- Fix 3: Make notify_is_deriving_reports_stop conditional
-- Previously this did an unconditional DELETE, which destroyed the
-- pipeline_progress row as soon as the serial derive_reports command
-- completed — before any of the actual Phase 2 work ran.
-- Now uses the same guard pattern as Phase 1's stop function.
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_reports_stop$
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
$notify_is_deriving_reports_stop$;

END;
