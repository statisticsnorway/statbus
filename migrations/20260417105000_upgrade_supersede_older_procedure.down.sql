-- Down migration for 20260417105000: drop the supersede procedure.
-- Callers (install.go, service.go) fall back to inline SQL.

DROP PROCEDURE IF EXISTS public.upgrade_supersede_older(text, integer);
