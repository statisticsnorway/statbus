-- Down Migration 20250227115859: add import jobs
BEGIN;

-- Drop triggers first
-- DROP TRIGGER validate_time_context_ident_trigger ON public.import_definition; -- Removed in UP
-- DROP TRIGGER validate_on_draft_change ON public.import_definition; -- Removed in UP
-- DROP TRIGGER prevent_non_draft_changes ON public.import_definition; -- Removed in UP
-- DROP TRIGGER prevent_non_draft_source_column_changes ON public.import_source_column; -- Removed in UP
-- DROP TRIGGER prevent_non_draft_mapping_changes ON public.import_mapping; -- Removed in UP
DROP TRIGGER IF EXISTS trg_validate_import_step_after_change ON public.import_step;
DROP TRIGGER IF EXISTS trg_validate_import_data_column_after_change ON public.import_data_column;
DROP TRIGGER IF EXISTS trg_validate_import_mapping_after_change ON public.import_mapping;
DROP TRIGGER IF EXISTS trg_validate_import_source_column_after_change ON public.import_source_column;
DROP TRIGGER IF EXISTS trg_validate_import_definition_step_after_change ON public.import_definition_step;
DROP TRIGGER IF EXISTS trg_validate_import_definition_after_change ON public.import_definition;
DROP TRIGGER IF EXISTS import_job_derive_trigger ON public.import_job;
DROP TRIGGER IF EXISTS import_job_generate ON public.import_job;
DROP TRIGGER IF EXISTS import_job_notify_trigger ON public.import_job;
DROP TRIGGER IF EXISTS import_job_cleanup ON public.import_job;
DROP TRIGGER IF EXISTS import_job_state_change_before_trigger ON public.import_job;
DROP TRIGGER IF EXISTS import_job_state_change_after_trigger ON public.import_job;
DROP TRIGGER IF EXISTS import_job_progress_update_trigger ON public.import_job;
DROP TRIGGER IF EXISTS import_job_progress_notify_trigger ON public.import_job;

-- RLS and Permissions for public.import_job
DROP POLICY IF EXISTS import_job_admin_user_manage ON public.import_job;
DROP POLICY IF EXISTS import_job_authenticated_select_own ON public.import_job;
DROP POLICY IF EXISTS import_job_regular_user_insert_own ON public.import_job;
DROP POLICY IF EXISTS import_job_regular_user_update_own ON public.import_job;
DROP POLICY IF EXISTS import_job_regular_user_delete_own ON public.import_job;
ALTER TABLE public.import_job DISABLE ROW LEVEL SECURITY;
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.import_job FROM regular_user;
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.import_job FROM admin_user;
REVOKE SELECT ON public.import_job FROM authenticated;

-- RLS and Permissions for tables affected by admin.add_rls_regular_user_can_read
-- Assuming policy names like <table>_regular_user_read_policy and regular_user as grantee.
-- Adjust policy names and grantee if admin.add_rls_regular_user_can_read behaves differently.

-- public.import_step
DROP POLICY IF EXISTS import_step_regular_user_read_policy ON public.import_step;
ALTER TABLE public.import_step DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_step FROM regular_user; -- Or appropriate role

-- public.import_data_column
DROP POLICY IF EXISTS import_data_column_regular_user_read_policy ON public.import_data_column;
ALTER TABLE public.import_data_column DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_data_column FROM regular_user; -- Or appropriate role

-- public.import_definition
DROP POLICY IF EXISTS import_definition_regular_user_read_policy ON public.import_definition;
ALTER TABLE public.import_definition DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_definition FROM regular_user; -- Or appropriate role

-- public.import_source_column
DROP POLICY IF EXISTS import_source_column_regular_user_read_policy ON public.import_source_column;
ALTER TABLE public.import_source_column DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_source_column FROM regular_user; -- Or appropriate role

-- public.import_mapping
DROP POLICY IF EXISTS import_mapping_regular_user_read_policy ON public.import_mapping;
ALTER TABLE public.import_mapping DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_mapping FROM regular_user; -- Or appropriate role

-- public.import_definition_step
DROP POLICY IF EXISTS import_definition_step_regular_user_read_policy ON public.import_definition_step;
ALTER TABLE public.import_definition_step DISABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.import_definition_step FROM regular_user; -- Or appropriate role

-- Drop the sequence for import job priorities
DROP SEQUENCE IF EXISTS public.import_job_priority_seq;

-- Revoke execute permissions on functions
REVOKE EXECUTE ON FUNCTION admin.set_import_job_user_context FROM authenticated;
REVOKE EXECUTE ON FUNCTION admin.reset_import_job_user_context FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_import_job_progress FROM authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA import FROM authenticated;

-- Revoke schema permissions
REVOKE USAGE ON SCHEMA import FROM authenticated;

-- Drop worker command registry entry
DELETE FROM worker.tasks WHERE command = 'import_job_process';
DELETE FROM worker.command_registry WHERE command = 'import_job_process';

-- Drop queue registry entry
DELETE FROM worker.queue_registry WHERE queue = 'import';

-- Drop functions
DROP FUNCTION IF EXISTS admin.check_import_job_state_for_insert();
DROP FUNCTION IF EXISTS admin.update_import_job_state_after_insert();
DROP FUNCTION IF EXISTS admin.import_job_state_change_before();
DROP FUNCTION IF EXISTS admin.import_job_state_change_after();
DROP FUNCTION IF EXISTS admin.import_job_progress_update();
DROP FUNCTION IF EXISTS admin.import_job_progress_notify();
DROP FUNCTION IF EXISTS public.get_import_job_progress(integer);
DROP PROCEDURE IF EXISTS admin.import_job_process(payload JSONB);
DROP PROCEDURE IF EXISTS admin.import_job_process(integer);
DROP FUNCTION IF EXISTS admin.import_job_process_phase(public.import_job, public.import_step_phase); -- Added missing drop
DROP FUNCTION IF EXISTS admin.import_job_prepare(public.import_job);
DROP FUNCTION IF EXISTS admin.import_job_cleanup();
DROP FUNCTION IF EXISTS admin.import_job_generate(public.import_job);
DROP FUNCTION IF EXISTS admin.import_job_generate();
DROP FUNCTION IF EXISTS admin.import_job_notify();
DROP FUNCTION IF EXISTS admin.import_job_derive();
DROP PROCEDURE IF EXISTS worker.notify_check_is_importing();
DROP FUNCTION IF EXISTS admin.trigger_validate_import_definition();
DROP FUNCTION IF EXISTS admin.validate_import_definition(INT);
DROP FUNCTION IF EXISTS admin.import_job_next_state(public.import_job);
DROP FUNCTION IF EXISTS admin.import_job_set_state(public.import_job, public.import_job_state);
DROP FUNCTION IF EXISTS admin.set_import_job_user_context(integer);
DROP FUNCTION IF EXISTS admin.reset_import_job_user_context();
-- DROP FUNCTION admin.import_definition_validate_before(); -- Removed in UP
-- DROP FUNCTION admin.prevent_changes_to_non_draft_definition(); -- Removed in UP
-- DROP FUNCTION admin.validate_time_context_ident(); -- Removed in UP
DROP FUNCTION IF EXISTS admin.enqueue_import_job_process(integer);
DROP FUNCTION IF EXISTS admin.reschedule_import_job_process(integer);
DROP FUNCTION IF EXISTS import.safe_cast_to_ltree(text);

-- Drop views (if any were created - none in the UP script)
-- DROP VIEW public.import_information;

-- Drop tables in reverse order of creation
DROP INDEX IF EXISTS public.idx_unique_target_mapping_when_not_ignored;
DROP TABLE IF EXISTS public.import_mapping;
DROP TABLE IF EXISTS public.import_source_column;
DROP TABLE IF EXISTS public.import_job;
DROP TABLE IF EXISTS public.import_definition_step;
DROP TABLE IF EXISTS public.import_data_column;
DROP TABLE IF EXISTS public.import_definition;
DROP TABLE IF EXISTS public.import_step;

-- Drop types
DROP TYPE IF EXISTS public.import_job_state;
DROP TYPE IF EXISTS public.import_source_expression;
DROP TYPE IF EXISTS public.import_data_state;
DROP TYPE IF EXISTS public.import_data_column_purpose;
DROP TYPE IF EXISTS public.import_strategy;
DROP TYPE IF EXISTS public.import_step_phase;
DROP TYPE IF EXISTS public.import_row_action_type;
DROP TYPE IF EXISTS public.import_row_operation_type;
DROP TYPE IF EXISTS public.import_mode;

-- Drop schema
DROP SCHEMA IF EXISTS import CASCADE; -- Use CASCADE to remove objects within the schema if any were missed or if order is tricky

END;
