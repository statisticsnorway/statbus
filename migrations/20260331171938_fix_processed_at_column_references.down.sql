-- Down Migration 20260331171938: fix_processed_at_column_references
-- Restores the (broken) functions with processed_at references.
BEGIN;

CREATE OR REPLACE PROCEDURE worker.command_task_cleanup(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $command_task_cleanup$
DECLARE
    v_completed_retention_days INT = COALESCE((payload->>'completed_retention_days')::int, 7);
    v_failed_retention_days INT = COALESCE((payload->>'failed_retention_days')::int, 30);
BEGIN
    DELETE FROM worker.tasks
    WHERE state = 'completed'::worker.task_state
      AND processed_at < (now() - (v_completed_retention_days || ' days')::interval);

    DELETE FROM worker.tasks
    WHERE state = 'failed'::worker.task_state
      AND processed_at < (now() - (v_failed_retention_days || ' days')::interval);

    PERFORM worker.enqueue_task_cleanup(
      v_completed_retention_days,
      v_failed_retention_days
    );
END;
$command_task_cleanup$;

CREATE OR REPLACE FUNCTION worker.enqueue_import_job_cleanup()
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_import_job_cleanup$
DECLARE
  v_task_id BIGINT;
BEGIN
  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'import_job_cleanup',
    '{}'::jsonb,
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'import_job_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = EXCLUDED.payload,
    scheduled_at = EXCLUDED.scheduled_at,
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$enqueue_import_job_cleanup$;

CREATE OR REPLACE FUNCTION worker.enqueue_task_cleanup(
  p_completed_retention_days INT DEFAULT 7,
  p_failed_retention_days INT DEFAULT 30
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_task_cleanup$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'completed_retention_days', p_completed_retention_days,
    'failed_retention_days', p_failed_retention_days
  );

  INSERT INTO worker.tasks (
    command,
    payload,
    scheduled_at
  ) VALUES (
    'task_cleanup',
    v_payload,
    now() + interval '24 hours'
  )
  ON CONFLICT (command) WHERE command = 'task_cleanup' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    state = 'pending'::worker.task_state,
    priority = EXCLUDED.priority,
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'maintenance');

  RETURN v_task_id;
END;
$enqueue_task_cleanup$;

END;
