-- Migration: import_job_procedures_for_stats (Rollback)
BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_tags(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS import.process_tags(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
