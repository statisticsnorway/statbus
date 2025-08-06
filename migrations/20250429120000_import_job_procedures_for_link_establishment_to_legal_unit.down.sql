-- Migration: (Rollback)

BEGIN;

DROP PROCEDURE import.analyse_link_establishment_to_legal_unit(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT);

COMMIT;
