-- Migration: implement_base_legal_unit_procedures (Rollback)

BEGIN;

DROP FUNCTION IF EXISTS admin.safe_cast_to_date(TEXT);

DROP PROCEDURE admin.analyse_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP PROCEDURE admin.process_legal_unit(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);

COMMIT;
