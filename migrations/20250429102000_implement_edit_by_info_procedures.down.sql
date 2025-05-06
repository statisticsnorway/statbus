-- Migration: implement_edit_by_info_procedures (Rollback)

BEGIN;

DROP PROCEDURE admin.analyse_edit_info(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

COMMIT;
