-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE import.analyse_edit_info(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
