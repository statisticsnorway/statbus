-- Down Migration 20260711201432: upgrade state log instrumentation statbus 154
BEGIN;

DROP TRIGGER upgrade_state_log_trigger ON public.upgrade;
DROP FUNCTION public.upgrade_state_log_capture();
DROP TABLE public.upgrade_state_log;

END;
