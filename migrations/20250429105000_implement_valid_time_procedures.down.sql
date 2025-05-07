-- Migration: implement_valid_time_procedures (Rollback)
-- Reverts the procedures to placeholders or drops them.

BEGIN;

DROP FUNCTION IF EXISTS admin.safe_cast_to_date(TEXT);
DROP PROCEDURE IF EXISTS admin.analyse_valid_time_from_context(INT, BIGINT[], TEXT);
DROP PROCEDURE IF EXISTS admin.analyse_valid_time_from_source(INT, BIGINT[], TEXT);

COMMIT;
