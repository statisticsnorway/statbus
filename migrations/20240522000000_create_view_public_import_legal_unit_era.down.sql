BEGIN;

CALL lifecycle_callbacks.del('import_legal_unit_era');
CALL admin.cleanup_import_legal_unit_era();

DROP PROCEDURE admin.generate_import_legal_unit_era();
DROP PROCEDURE admin.cleanup_import_legal_unit_era();

END;
