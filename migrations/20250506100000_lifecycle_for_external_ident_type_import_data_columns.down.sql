BEGIN;

-- Remove the lifecycle callback registration
CALL lifecycle_callbacks.del('import_external_ident_data_columns');

-- Remove the functions from the corresponding up migration
DROP PROCEDURE IF EXISTS admin.generate_external_ident_data_columns();
DROP PROCEDURE IF EXISTS admin.cleanup_external_ident_data_columns();

END;
