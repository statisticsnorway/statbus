BEGIN;

-- Set search_path on all SECURITY DEFINER functions/procedures that are missing it.
-- Without an explicit search_path, SECURITY DEFINER functions execute with the
-- session's search_path, which could be manipulated to hijack function resolution
-- (privilege escalation vector).
--
-- Pattern: search_path = public, <own_schema>, pg_temp
-- Already configured (skipped): admin.set_optimal_import_session_settings, auth.jwt_verify

-- === admin schema (4 functions + 2 procedures) ===
ALTER FUNCTION admin.import_job_cleanup() SET search_path = public, admin, pg_temp;
ALTER FUNCTION admin.import_job_generate(import_job) SET search_path = public, admin, pg_temp;
ALTER FUNCTION admin.reset_import_job_user_context() SET search_path = public, admin, pg_temp;
ALTER FUNCTION admin.set_import_job_user_context(integer) SET search_path = public, admin, pg_temp;
ALTER PROCEDURE admin.disable_temporal_triggers() SET search_path = public, admin, pg_temp;
ALTER PROCEDURE admin.enable_temporal_triggers() SET search_path = public, admin, pg_temp;

-- === auth schema (6 functions) ===
ALTER FUNCTION auth.auto_create_api_token_on_confirmation() SET search_path = public, auth, pg_temp;
ALTER FUNCTION auth.check_api_key_revocation() SET search_path = public, auth, pg_temp;
ALTER FUNCTION auth.cleanup_expired_sessions() SET search_path = public, auth, pg_temp;
ALTER FUNCTION auth.drop_user_role() SET search_path = public, auth, pg_temp;
ALTER FUNCTION auth.generate_api_key_token() SET search_path = public, auth, pg_temp;
ALTER FUNCTION auth.sync_user_credentials_and_roles() SET search_path = public, auth, pg_temp;

-- === graphql schema (2 functions) ===
ALTER FUNCTION graphql.get_schema_version() SET search_path = public, graphql, pg_temp;
ALTER FUNCTION graphql.increment_schema_version() SET search_path = public, graphql, pg_temp;

-- === lifecycle_callbacks schema (1 function) ===
ALTER FUNCTION lifecycle_callbacks.cleanup_and_generate() SET search_path = public, lifecycle_callbacks, pg_temp;

-- === public schema (14 functions, 3 converted to INVOKER) ===
ALTER FUNCTION public.activity_category_used_derive() SET search_path = public, pg_temp;
ALTER FUNCTION public.auth_expire_access_keep_refresh() SET search_path = public, pg_temp;
ALTER FUNCTION public.auth_status() SET search_path = public, pg_temp;
ALTER FUNCTION public.data_source_used_derive() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_import_job_progress(integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_active_sessions() SET search_path = public, pg_temp;
ALTER FUNCTION public.login(text, text) SET search_path = public, pg_temp;
ALTER FUNCTION public.logout() SET search_path = public, pg_temp;
ALTER FUNCTION public.refresh() SET search_path = public, pg_temp;
ALTER FUNCTION public.region_used_derive() SET search_path = public, pg_temp;
ALTER FUNCTION public.revoke_session(uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.sector_used_derive() SET search_path = public, pg_temp;
ALTER FUNCTION public.statistical_history_drilldown(statistical_unit_type, history_resolution, integer, ltree, ltree, ltree, integer, integer, integer, integer, integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.statistical_unit_facet_drilldown(statistical_unit_type, ltree, ltree, ltree, integer, integer, integer, date) SET search_path = public, pg_temp;

-- Convert 3 functions from DEFINER to INVOKER.
-- These only read worker.tasks which has no RLS and grants SELECT to authenticated.
-- They don't need DEFINER privileges.
ALTER FUNCTION public.is_importing() SECURITY INVOKER;
ALTER FUNCTION public.is_deriving_reports() SECURITY INVOKER;
ALTER FUNCTION public.is_deriving_statistical_units() SECURITY INVOKER;

-- === worker schema (17 procedures) ===
ALTER PROCEDURE worker.command_collect_changes(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.command_import_job_cleanup(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.command_task_cleanup(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_reports(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_history(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_history_facet(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_history_facet_period(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_history_period(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_unit(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.statistical_history_reduce(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.statistical_history_facet_reduce(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_unit_continue(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_unit_facet(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.derive_statistical_unit_facet_partition(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.statistical_unit_facet_reduce(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.statistical_unit_flush_staging(jsonb) SET search_path = public, worker, pg_temp;
ALTER PROCEDURE worker.statistical_unit_refresh_batch(jsonb) SET search_path = public, worker, pg_temp;

END;
