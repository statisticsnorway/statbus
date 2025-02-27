-- Down Migration 20250227115859: add import jobs
BEGIN;

-- First delete all import jobs to trigger cleanup
DELETE FROM public.import_job;

-- Drop all import definitions (will cascade to mappings and source columns)
DELETE FROM public.import_definition;

-- Drop functions and triggers
DROP FUNCTION IF EXISTS admin.import_job_process(integer);
DROP FUNCTION IF EXISTS admin.import_job_cleanup(public.import_job);
DROP FUNCTION IF EXISTS admin.import_job_generate(public.import_job);
DROP FUNCTION IF EXISTS admin.import_job_generate();
DROP FUNCTION IF EXISTS admin.import_job_derive();
DROP FUNCTION IF EXISTS admin.import_definition_validate_before();
DROP FUNCTION IF EXISTS admin.prevent_changes_to_non_draft_definition();
DROP FUNCTION IF EXISTS validate_time_context_ident();

-- Drop views
DROP VIEW IF EXISTS public.import_information;

-- Drop tables in reverse order
DROP TABLE IF EXISTS public.import_mapping;
DROP TABLE IF EXISTS public.import_source_column;
DROP TABLE IF EXISTS public.import_job;
DROP TABLE IF EXISTS public.import_definition;
DROP TABLE IF EXISTS public.import_target_column;
DROP TABLE IF EXISTS public.import_target;

-- Drop types
DROP TYPE IF EXISTS public.import_job_status;
DROP TYPE IF EXISTS public.import_source_expression;

END;
