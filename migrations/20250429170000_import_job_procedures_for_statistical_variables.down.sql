-- Migration: implement_stats_procedures (Rollback)
BEGIN;

DROP PROCEDURE import.analyse_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE import.process_statistical_variables(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP FUNCTION IF EXISTS import.safe_cast_to_integer(TEXT);
DROP FUNCTION IF EXISTS import.safe_cast_to_boolean(TEXT);

COMMIT;
