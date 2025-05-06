-- Migration: implement_contact_procedures (Rollback)
BEGIN;

DROP PROCEDURE admin.analyse_contact(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP PROCEDURE admin.process_contact(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

COMMIT;
