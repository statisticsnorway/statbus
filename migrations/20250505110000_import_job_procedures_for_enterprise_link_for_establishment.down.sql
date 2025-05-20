-- Migration: import_job_procedures_for_enterprise_link_for_establishment (Rollback)
BEGIN;

DROP PROCEDURE import.analyse_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE import.process_enterprise_link_for_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
