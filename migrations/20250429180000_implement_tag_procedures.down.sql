-- Migration: implement_tag_procedures (Rollback)
BEGIN;

DROP PROCEDURE IF EXISTS admin.analyse_tags(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP PROCEDURE IF EXISTS admin.process_tags(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT);
DROP FUNCTION IF EXISTS public.tag_find_by_path(TEXT); -- Renamed function

COMMIT;
