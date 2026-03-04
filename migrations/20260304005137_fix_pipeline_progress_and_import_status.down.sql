BEGIN;

-- Restore original is_importing() without 'preparing_data'
CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', EXISTS (
      SELECT 1 FROM public.import_job
      WHERE state IN ('analysing_data', 'processing_data')
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
      WHERE ij.state IN ('analysing_data', 'processing_data')),
      '[]'::jsonb
    )
  );
$function$;

-- Restore original notify_is_deriving_statistical_units_stop (without collect_changes exclusion)
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_statistical_units_stop$
BEGIN
  -- Check if any Phase 1 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 1 tasks that still need to run.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_statistical_units'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 1 work pending, don't stop yet
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$notify_is_deriving_statistical_units_stop$;

-- Restore original unconditional notify_is_deriving_reports_stop
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Only fires for last Phase 2 step (via after_procedure on derive_reports).
  -- Same pattern as Phase 1: unconditionally delete and notify.
  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_reports';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_reports', 'status', false)::text
  );
END;
$procedure$;

END;
