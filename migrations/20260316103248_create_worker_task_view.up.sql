BEGIN;

-- ============================================================================
-- PUBLIC VIEW: worker_task
-- ============================================================================
-- Exposes worker.tasks + command_registry metadata via PostgREST.
-- The worker schema is not in PGRST_DB_SCHEMAS, so we need a public view.
--
-- No UNION ALL trick: it prevents LIMIT pushdown, causing full table scans
-- (46s for 15k rows). Without it: 4ms via Index Scan Backward on tasks_pkey.
-- Prototype verified in tmp/worker_task_view_prototype.sql.

CREATE VIEW public.worker_task WITH (security_invoker = on) AS
SELECT
  t.id,
  t.command,
  t.priority,
  t.state,
  t.parent_id,
  t.depth,
  t.child_mode,
  t.created_at,
  t.processed_at,
  t.completed_at,
  t.duration_ms,
  t.error,
  t.scheduled_at,
  t.worker_pid,
  t.payload,
  cr.queue,
  cr.description AS command_description
FROM worker.tasks AS t
JOIN worker.command_registry AS cr ON cr.command = t.command;

-- Grant access for PostgREST (authenticated) and user roles.
-- security_invoker = on means the caller's privileges apply to the underlying
-- tables, so we must grant SELECT on them to roles that will query the view.
GRANT SELECT ON public.worker_task TO authenticated, admin_user;
GRANT SELECT ON worker.tasks TO regular_user;
GRANT SELECT ON worker.command_registry TO regular_user;

END;
