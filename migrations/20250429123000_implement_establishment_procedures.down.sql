BEGIN;

DROP PROCEDURE admin.analyse_establishment(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP PROCEDURE admin.process_establishment(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

END;
