-- Migration: (Rollback)
-- Reverts the procedures to placeholders or drops them.

BEGIN;

DROP FUNCTION IF EXISTS import.safe_cast_to_date(TEXT);
DROP PROCEDURE IF EXISTS import.analyse_valid_time_from_context(INT, INTEGER[], TEXT);
DROP PROCEDURE IF EXISTS import.analyse_valid_time_from_source(INT, INTEGER[], TEXT);

COMMIT;
