-- Migration: implement_external_ident_procedures (Rollback)

BEGIN;

DROP PROCEDURE IF EXISTS admin.analyse_external_idents(INT, TID[], TEXT);
DROP PROCEDURE IF EXISTS admin.process_external_idents(INT, TID[], TEXT); -- Though this one might not exist or have this signature

COMMIT;
