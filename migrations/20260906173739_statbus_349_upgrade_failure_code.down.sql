-- Down Migration 20260906173739: statbus_349_upgrade_failure_code
BEGIN;

ALTER TABLE public.upgrade
DROP COLUMN failure_code;

DROP TYPE public.upgrade_failure_code;

END;
