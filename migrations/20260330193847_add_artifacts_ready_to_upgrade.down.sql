-- Down Migration 20260330193847: add_artifacts_ready_to_upgrade
BEGIN;

ALTER TABLE public.upgrade DROP COLUMN IF EXISTS artifacts_ready;

END;
