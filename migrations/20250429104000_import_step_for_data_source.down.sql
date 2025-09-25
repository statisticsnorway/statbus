-- Down migration for data_source import step
BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_data_source(INT, INTEGER[], TEXT);

COMMIT;
