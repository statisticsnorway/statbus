-- Down Migration 20260421113651: upgrade_state_singletons
BEGIN;

DROP INDEX IF EXISTS public.upgrade_single_in_progress;
DROP INDEX IF EXISTS public.upgrade_single_scheduled;

END;
