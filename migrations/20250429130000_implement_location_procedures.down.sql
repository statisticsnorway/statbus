-- Migration: implement_location_procedures (Rollback)
BEGIN;

-- Drop procedures with the correct signature (including p_step_code TEXT)
DROP PROCEDURE IF EXISTS admin.analyse_location(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS admin.process_location(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP FUNCTION IF EXISTS admin.safe_cast_to_numeric(TEXT);

COMMIT;
