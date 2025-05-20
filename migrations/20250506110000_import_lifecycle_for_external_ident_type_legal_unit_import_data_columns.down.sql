BEGIN;

-- Remove the lifecycle callback registration
CALL lifecycle_callbacks.del('import_link_lu_data_columns');

-- Remove the functions from the up migration
DROP PROCEDURE IF EXISTS import.generate_link_lu_data_columns();
DROP PROCEDURE IF EXISTS import.cleanup_link_lu_data_columns();

END;
