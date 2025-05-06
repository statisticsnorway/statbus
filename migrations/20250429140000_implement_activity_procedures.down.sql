-- Migration: implement_activity_procedures (Rollback)
BEGIN;

-- Drop procedures with the correct signature (including p_step_code TEXT)
DROP PROCEDURE IF EXISTS admin.analyse_activity(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS admin.process_activity(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

COMMIT;
