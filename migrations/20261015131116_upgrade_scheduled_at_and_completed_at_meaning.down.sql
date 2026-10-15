-- Down Migration 20261015131116: upgrade scheduled_at and completed_at meaning
BEGIN;

COMMENT ON COLUMN public.upgrade.scheduled_at IS NULL;
COMMENT ON COLUMN public.upgrade.completed_at IS NULL;

END;
