-- Migration 20260711201432: upgrade state log instrumentation statbus 154
BEGIN;

-- STATBUS-154 INSTRUMENTATION — every writer of public.upgrade's state /
-- recovery_parked_at, captured at the DB layer. The convicted parked-completed
-- writer was OUTSIDE the blessed Go terminal-write path (plain Exec, no
-- logUpgradeRow marker — which is why the code-side grep for the writer missed
-- it), and several writers are not Go at all (the supersede procedure,
-- step-table psql). Only a DB trigger sees EVERY writer. Identity rides
-- STATBUS-149's application_name tags (each Go connection tags itself); the ops
-- plane writes this table at near-zero volume, so it stays tiny.
--
-- Read it when an upgrade row lands in an unexpected state:
--   SELECT * FROM public.upgrade_state_log WHERE upgrade_id = <id> ORDER BY id;

CREATE TABLE public.upgrade_state_log (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  upgrade_id       integer     NOT NULL,
  old_state        upgrade_state,
  new_state        upgrade_state,
  old_parked_at    timestamptz,
  new_parked_at    timestamptz,
  application_name text,
  query            text,
  backend_pid      integer,
  logged_at        timestamptz NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE public.upgrade_state_log IS
  'STATBUS-154 diagnostic append-only log: one row per public.upgrade UPDATE that changes state or recovery_parked_at, tagged with the writing connection identity (application_name / backend_pid / current_query). Ops-plane only.';

-- RLS mirrors public.upgrade: admin manages, authenticated may view. The
-- capture trigger below is SECURITY DEFINER so INSERTs land regardless of the
-- writer's role. A fresh table is deny-by-default to PostgREST anon/authenticated
-- until granted, so enabling RLS keeps it non-public by construction.
ALTER TABLE public.upgrade_state_log ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.upgrade_state_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.upgrade_state_log TO admin_user;

CREATE POLICY upgrade_state_log_admin_manage ON public.upgrade_state_log
  TO admin_user USING (true) WITH CHECK (true);
CREATE POLICY upgrade_state_log_authenticated_view ON public.upgrade_state_log
  FOR SELECT TO authenticated USING (true);

CREATE FUNCTION public.upgrade_state_log_capture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $upgrade_state_log_capture$
BEGIN
  INSERT INTO public.upgrade_state_log (
    upgrade_id, old_state, new_state, old_parked_at, new_parked_at,
    application_name, query, backend_pid, logged_at)
  VALUES (
    NEW.id, OLD.state, NEW.state, OLD.recovery_parked_at, NEW.recovery_parked_at,
    current_setting('application_name', true), current_query(),
    pg_backend_pid(), clock_timestamp());
  RETURN NEW;
END;
$upgrade_state_log_capture$;

CREATE TRIGGER upgrade_state_log_trigger
  AFTER UPDATE ON public.upgrade
  FOR EACH ROW
  WHEN (OLD.state IS DISTINCT FROM NEW.state
        OR OLD.recovery_parked_at IS DISTINCT FROM NEW.recovery_parked_at)
  EXECUTE FUNCTION public.upgrade_state_log_capture();

END;
