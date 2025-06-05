-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_external_idents(INT, BIGINT[], TEXT);
DROP PROCEDURE IF EXISTS import.shared_upsert_external_idents_for_unit(INT, TEXT, BIGINT, INT, TEXT, INT, TIMESTAMPTZ, TEXT);

COMMIT;
