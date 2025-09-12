-- Migration: (Rollback)
-- Reverts the procedures to placeholders or drops them.

BEGIN;

DROP FUNCTION IF EXISTS import.safe_cast_to_date(TEXT);
DROP PROCEDURE IF EXISTS import.analyse_valid_time(INT, INTEGER[], TEXT);

COMMIT;
