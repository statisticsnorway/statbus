-- Down Migration 20260311174120: Remove upgrade tracking tables
BEGIN;

DROP TABLE IF EXISTS public.system_info;
DROP TABLE IF EXISTS public.upgrade;
DROP TYPE IF EXISTS public.upgrade_channel;

END;
