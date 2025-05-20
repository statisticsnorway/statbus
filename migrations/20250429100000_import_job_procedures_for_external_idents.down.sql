-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_external_idents(INT, BIGINT[], TEXT);
DROP PROCEDURE IF EXISTS import.process_external_idents(JSONB, TEXT);

COMMIT;
