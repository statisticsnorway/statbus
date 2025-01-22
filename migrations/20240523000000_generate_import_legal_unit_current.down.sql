BEGIN;

CALL lifecycle_callbacks.del('import_legal_unit_current');
CALL admin.cleanup_import_legal_unit_current();

DROP PROCEDURE admin.generate_import_legal_unit_current();
DROP PROCEDURE admin.cleanup_import_legal_unit_current();

END;
