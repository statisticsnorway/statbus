-- Down migration for 20260416112355_upgrade_retention_plan_apply.
-- Drops everything the up migration created, in reverse dependency order:
--   procedure → planner function → caps table → family helpers.

BEGIN;

DROP PROCEDURE IF EXISTS public.upgrade_retention_apply(text, integer, integer);
DROP FUNCTION  IF EXISTS public.upgrade_retention_plan(text, integer);
DROP TABLE     IF EXISTS public.upgrade_retention_caps;
DROP FUNCTION  IF EXISTS public.upgrade_family(public.upgrade);
DROP FUNCTION  IF EXISTS public.version_family(text);

END;
