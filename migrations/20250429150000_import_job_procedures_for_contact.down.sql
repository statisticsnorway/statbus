-- Migration: import_job_procedures_for_contact (Rollback)
BEGIN;

DROP PROCEDURE import.analyse_contact(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE import.process_contact(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
