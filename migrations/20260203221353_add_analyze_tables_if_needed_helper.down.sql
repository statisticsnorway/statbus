-- Down Migration 20260203221353: add_analyze_tables_if_needed_helper
BEGIN;

DROP FUNCTION IF EXISTS admin.analyze_tables_if_needed(regclass[], numeric, integer);

END;
