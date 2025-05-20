-- Migration: (Rollback) import_job_procedures_for_status

BEGIN;

DROP PROCEDURE IF EXISTS import.analyse_status(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
