-- Migration: implement_base_legal_unit_procedures (Rollback)

BEGIN;

DROP FUNCTION IF EXISTS admin.safe_cast_to_date(TEXT);

DROP PROCEDURE IF EXISTS admin.analyse_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS admin.process_legal_unit(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
