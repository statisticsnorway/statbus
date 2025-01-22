BEGIN;
CALL lifecycle_callbacks.del('import_establishment_current');
CALL admin.cleanup_import_establishment_current();

DROP PROCEDURE admin.generate_import_establishment_current();
DROP PROCEDURE admin.cleanup_import_establishment_current();

END;
