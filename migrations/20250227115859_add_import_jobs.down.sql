-- Down Migration 20250227115859: add import jobs
BEGIN;

-- First delete all import jobs to trigger cleanup
TRUNCATE public.import_job, public.import_mapping, public.import_source_column, public.import_definition;

-- Drop triggers first
DROP TRIGGER validate_time_context_ident_trigger ON public.import_definition;
DROP TRIGGER validate_on_draft_change ON public.import_definition;
DROP TRIGGER prevent_non_draft_changes ON public.import_definition;
DROP TRIGGER prevent_non_draft_source_column_changes ON public.import_source_column;
DROP TRIGGER prevent_non_draft_mapping_changes ON public.import_mapping;
DROP TRIGGER import_job_derive_trigger ON public.import_job;
DROP TRIGGER import_job_generate ON public.import_job;
DROP TRIGGER import_job_cleanup ON public.import_job;
DROP TRIGGER import_job_status_change_trigger ON public.import_job;

-- Revoke execute permissions on user context functions
REVOKE EXECUTE ON FUNCTION admin.set_import_job_user_context FROM authenticated;
REVOKE EXECUTE ON FUNCTION admin.reset_import_job_user_context FROM authenticated;

-- Drop worker command registry entry
DELETE FROM worker.command_registry WHERE command = 'import_job_process';

-- Drop queue registry entry
DELETE FROM worker.queue_registry WHERE queue = 'import';

-- Drop functions
DROP FUNCTION admin.import_job_status_change();
DROP FUNCTION admin.import_job_process(payload JSONB);
DROP FUNCTION admin.import_job_process(integer);
DROP FUNCTION admin.import_job_prepare(public.import_job);
DROP FUNCTION admin.import_job_analyse(public.import_job);
DROP FUNCTION admin.import_job_insert(public.import_job);
DROP FUNCTION admin.import_job_cleanup();
DROP FUNCTION admin.import_job_generate(public.import_job);
DROP FUNCTION admin.import_job_generate();
DROP FUNCTION admin.import_job_derive();
DROP FUNCTION admin.import_job_next_state(public.import_job);
DROP FUNCTION admin.import_job_set_status(public.import_job, public.import_job_status);
DROP FUNCTION admin.set_import_job_user_context(integer);
DROP FUNCTION admin.reset_import_job_user_context();
DROP FUNCTION admin.import_definition_validate_before();
DROP FUNCTION admin.prevent_changes_to_non_draft_definition();
DROP FUNCTION admin.validate_time_context_ident();
DROP FUNCTION admin.enqueue_import_job_process(integer);

-- Drop views
DROP VIEW public.import_information;

-- Drop tables in reverse order
DROP TABLE public.import_mapping;
DROP TABLE public.import_source_column;
DROP TABLE public.import_job;
DROP TABLE public.import_definition;
DROP TABLE public.import_target_column;
DROP TABLE public.import_target;

-- Drop types
DROP TYPE public.import_job_status;
DROP TYPE public.import_source_expression;

END;
