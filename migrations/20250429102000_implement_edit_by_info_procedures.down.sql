-- Migration: implement_edit_by_info_procedures (Rollback)

BEGIN;

DROP PROCEDURE admin.analyse_edit_info(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

COMMIT;
