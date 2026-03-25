-- Migration 20260324200723: notify_progress_before_phase_handlers
-- Fix: Pipeline progress UI appears late because pg_notify is transactional.
-- The before_procedure runs and commits BEFORE the handler, so the notification
-- is delivered immediately when the phase starts processing.
BEGIN;

UPDATE worker.command_registry
SET before_procedure = 'worker.notify_task_progress'
WHERE command IN ('derive_units_phase', 'derive_reports_phase');

END;
