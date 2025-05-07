-- Migration: implement_tag_procedures (Rollback)
BEGIN;

DROP PROCEDURE IF EXISTS admin.analyse_tags(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS admin.process_tags(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT);
DROP FUNCTION IF EXISTS public.tag_find_by_path(TEXT);

COMMIT;
