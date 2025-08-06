-- Migration: (Rollback)

BEGIN;

DROP FUNCTION IF EXISTS import.safe_cast_to_date(TEXT);

DROP PROCEDURE IF EXISTS import.analyse_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS import.process_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
