-- Migration 20261109111905: admins can recalculate all statistical units and reports
BEGIN;

CREATE FUNCTION public.recalculate_all()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $recalculate_all$
BEGIN
    RETURN worker.enqueue_derive_statistical_unit_all();
END;
$recalculate_all$;

COMMENT ON FUNCTION public.recalculate_all() IS
    'Schedules a full recalculation: every statistical unit over all time, then every report. Returns the collect_changes task id, or NULL when the database holds no units. The workers do the work; progress shows as is_deriving_statistical_units and then is_deriving_reports. This is the command palette''s "Recalculate all" for administrators, the same full refresh migrations schedule. SECURITY DEFINER because the worker queue is not writable by application roles; EXECUTE is granted to admin_user only, so the database, not the button, decides who may run it.';

-- sql_saga_health_checks rejects privilege statements it does not expect;
-- the established guard (migration 20260223185108) brackets them.
ALTER EVENT TRIGGER sql_saga_health_checks DISABLE;
REVOKE EXECUTE ON FUNCTION public.recalculate_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_all() TO admin_user;
ALTER EVENT TRIGGER sql_saga_health_checks ENABLE;

END;
