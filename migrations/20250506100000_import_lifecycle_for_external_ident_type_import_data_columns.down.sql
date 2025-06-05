BEGIN;

-- Remove the lifecycle callback registration
CALL lifecycle_callbacks.del('import_external_ident_data_columns');

-- Remove the functions from the corresponding up migration
DROP PROCEDURE IF EXISTS import.generate_external_ident_data_columns();
DROP PROCEDURE IF EXISTS import.cleanup_external_ident_data_columns();

END;
