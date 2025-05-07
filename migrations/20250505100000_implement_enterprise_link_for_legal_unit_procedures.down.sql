-- Migration: implement_enterprise_link_for_legal_unit_procedures (Rollback)
BEGIN;

DROP PROCEDURE admin.analyse_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE admin.process_enterprise_link_for_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
