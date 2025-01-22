BEGIN;

CALL admin.cleanup_import_establishment_current_without_legal_unit();
CALL lifecycle_callbacks.del('import_establishment_current_without_legal_unit');
DROP PROCEDURE admin.generate_import_establishment_current_without_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_current_without_legal_unit();

END;
