-- Down Migration 20260324200723: notify_progress_before_phase_handlers
BEGIN;

UPDATE worker.command_registry
SET before_procedure = NULL
WHERE command IN ('derive_units_phase', 'derive_reports_phase');

END;
