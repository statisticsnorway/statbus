-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_external_idents(INT, INTEGER[], TEXT);
DROP PROCEDURE IF EXISTS import.shared_upsert_external_idents_for_unit(INT, TEXT, INTEGER, INT, TEXT, INT, TIMESTAMPTZ, TEXT);

COMMIT;
