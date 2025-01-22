BEGIN;
CALL lifecycle_callbacks.del('import_establishment_era_for_legal_unit');
CALL admin.cleanup_import_establishment_era_for_legal_unit();

DROP PROCEDURE admin.generate_import_establishment_era_for_legal_unit();
DROP PROCEDURE admin.cleanup_import_establishment_era_for_legal_unit();

END;
