BEGIN;

CALL lifecycle_callbacks.del('import_establishment_era');
CALL admin.cleanup_import_establishment_era();

DROP PROCEDURE admin.generate_import_establishment_era();
DROP PROCEDURE admin.cleanup_import_establishment_era();

END;
