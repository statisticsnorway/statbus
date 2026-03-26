-- Migration 20260326004538: notify_frontend_on_upgrade_changes
BEGIN;

-- Notify the frontend via the existing worker_status channel when upgrade rows change.
-- The db-listener already LISTENs on worker_status, and the SSE endpoint delivers it
-- to browsers. The frontend dispatches on payload.type === 'upgrade_changed'.
CREATE OR REPLACE FUNCTION public.upgrade_notify_frontend()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $upgrade_notify_frontend$
BEGIN
  PERFORM pg_notify('worker_status', '{"type":"upgrade_changed"}');
  RETURN COALESCE(NEW, OLD);
END;
$upgrade_notify_frontend$;

CREATE TRIGGER upgrade_notify_frontend_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.upgrade
  FOR EACH ROW
  EXECUTE FUNCTION public.upgrade_notify_frontend();

END;
