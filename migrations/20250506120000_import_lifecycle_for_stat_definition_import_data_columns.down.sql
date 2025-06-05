BEGIN;
-- Remove the lifecycle callback registration
CALL lifecycle_callbacks.del('import_stat_var_data_columns');

-- Remove the functions from the up migration
DROP PROCEDURE IF EXISTS import.generate_stat_var_data_columns();
DROP PROCEDURE IF EXISTS import.cleanup_stat_var_data_columns();

END;
