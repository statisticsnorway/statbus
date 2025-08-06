-- Migration: import_job_procedures_for_location (Rollback)
BEGIN;

-- Drop procedures with the correct signature (including p_step_code TEXT)
DROP PROCEDURE IF EXISTS import.analyse_location(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS import.process_location(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP FUNCTION IF EXISTS import.safe_cast_to_numeric(TEXT);

COMMIT;
