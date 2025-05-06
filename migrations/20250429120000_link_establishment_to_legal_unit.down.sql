-- Migration: implement_establishment_link_procedures (Rollback)

BEGIN;

DROP PROCEDURE admin.analyse_link_establishment_to_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

COMMIT;
