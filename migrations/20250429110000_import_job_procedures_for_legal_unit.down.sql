-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS import.process_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
