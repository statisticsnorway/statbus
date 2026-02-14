BEGIN;

-- Reset search_path on all functions/procedures
ALTER FUNCTION admin.import_job_cleanup() RESET search_path;
ALTER FUNCTION admin.import_job_generate(import_job) RESET search_path;
ALTER FUNCTION admin.reset_import_job_user_context() RESET search_path;
ALTER FUNCTION admin.set_import_job_user_context(integer) RESET search_path;
ALTER PROCEDURE admin.disable_temporal_triggers() RESET search_path;
ALTER PROCEDURE admin.enable_temporal_triggers() RESET search_path;

ALTER FUNCTION auth.auto_create_api_token_on_confirmation() RESET search_path;
ALTER FUNCTION auth.check_api_key_revocation() RESET search_path;
ALTER FUNCTION auth.cleanup_expired_sessions() RESET search_path;
ALTER FUNCTION auth.drop_user_role() RESET search_path;
ALTER FUNCTION auth.generate_api_key_token() RESET search_path;
ALTER FUNCTION auth.sync_user_credentials_and_roles() RESET search_path;

ALTER FUNCTION graphql.get_schema_version() RESET search_path;
ALTER FUNCTION graphql.increment_schema_version() RESET search_path;

ALTER FUNCTION lifecycle_callbacks.cleanup_and_generate() RESET search_path;

ALTER FUNCTION public.activity_category_used_derive() RESET search_path;
ALTER FUNCTION public.auth_expire_access_keep_refresh() RESET search_path;
ALTER FUNCTION public.auth_status() RESET search_path;
ALTER FUNCTION public.data_source_used_derive() RESET search_path;
ALTER FUNCTION public.get_import_job_progress(integer) RESET search_path;
ALTER FUNCTION public.list_active_sessions() RESET search_path;
ALTER FUNCTION public.login(text, text) RESET search_path;
ALTER FUNCTION public.logout() RESET search_path;
ALTER FUNCTION public.refresh() RESET search_path;
ALTER FUNCTION public.region_used_derive() RESET search_path;
ALTER FUNCTION public.revoke_session(uuid) RESET search_path;
ALTER FUNCTION public.sector_used_derive() RESET search_path;
ALTER FUNCTION public.statistical_history_drilldown(statistical_unit_type, history_resolution, integer, ltree, ltree, ltree, integer, integer, integer, integer, integer) RESET search_path;
ALTER FUNCTION public.statistical_unit_facet_drilldown(statistical_unit_type, ltree, ltree, ltree, integer, integer, integer, date) RESET search_path;

-- Restore SECURITY DEFINER on the 3 converted functions
ALTER FUNCTION public.is_importing() SECURITY DEFINER;
ALTER FUNCTION public.is_deriving_reports() SECURITY DEFINER;
ALTER FUNCTION public.is_deriving_statistical_units() SECURITY DEFINER;

ALTER PROCEDURE worker.command_collect_changes(jsonb) RESET search_path;
ALTER PROCEDURE worker.command_import_job_cleanup(jsonb) RESET search_path;
ALTER PROCEDURE worker.command_task_cleanup(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_reports(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_history(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_history_facet(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_history_facet_period(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_history_period(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_unit(jsonb) RESET search_path;
ALTER PROCEDURE worker.statistical_history_reduce(jsonb) RESET search_path;
ALTER PROCEDURE worker.statistical_history_facet_reduce(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_unit_continue(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_unit_facet(jsonb) RESET search_path;
ALTER PROCEDURE worker.derive_statistical_unit_facet_partition(jsonb) RESET search_path;
ALTER PROCEDURE worker.statistical_unit_facet_reduce(jsonb) RESET search_path;
ALTER PROCEDURE worker.statistical_unit_flush_staging(jsonb) RESET search_path;
ALTER PROCEDURE worker.statistical_unit_refresh_batch(jsonb) RESET search_path;

END;
