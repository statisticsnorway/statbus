BEGIN;

DROP PROCEDURE import.analyse_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE import.process_establishment(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);

END;
