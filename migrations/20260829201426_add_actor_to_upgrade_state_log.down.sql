-- Down migration: restore public.upgrade_state_log_capture() to its
-- pre-STATBUS-317 form (dumped via \sf immediately before this migration
-- was authored -- the exact prior bytes, per house convention), and drop
-- the actor/actor_source columns + the upgrade_actor_source type.
--
-- Safe to drop the columns outright: they carry no data this down migration
-- has any obligation to preserve differently from the columns themselves --
-- unlike a data-repair migration's down, there is no "correct data a fix
-- produced" here to protect, only an audit trail whose absence after
-- rollback is the expected, honest consequence of removing the mechanism
-- that wrote it.

BEGIN;

CREATE OR REPLACE FUNCTION public.upgrade_state_log_capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

ALTER TABLE public.upgrade_state_log
    DROP COLUMN actor,
    DROP COLUMN actor_source;

DROP TYPE public.upgrade_actor_source;

COMMIT;
