-- Migration: import_job_procedures_for_activity (Rollback)
BEGIN;

-- Drop procedures with the correct signature (including p_step_code TEXT)
DROP PROCEDURE IF EXISTS import.analyse_activity(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS import.process_activity(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
