-- Migration: import_job_procedures_for_enterprise_link_for_legal_unit (Rollback)
BEGIN;

DROP PROCEDURE import.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);
DROP PROCEDURE import.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
