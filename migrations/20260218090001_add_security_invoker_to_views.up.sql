BEGIN;

-- Add security_invoker=on to views that are currently missing it.
-- Without this, views run as the view owner (postgres), bypassing RLS on
-- underlying tables. With security_invoker=on, views execute using the
-- calling user's privileges, ensuring RLS is enforced.
--
-- NOT included:
--   __for_portion_of_valid views (8) — fixed in sql_saga source instead
--   Extension views: pg_stat_monitor, pg_stat_statements, pg_stat_statements_info,
--     hypopg_hidden_indexes, hypopg_list_indexes
--   sql_saga.information_schema__era — sql_saga internal
--   public.user — intentionally uses security_barrier=true without security_invoker;
--     needs to bypass RLS on auth.user to show user list

-- _def views (13)
ALTER VIEW public.activity_category_used_def SET (security_invoker = on);
ALTER VIEW public.country_used_def SET (security_invoker = on);
ALTER VIEW public.data_source_used_def SET (security_invoker = on);
ALTER VIEW public.legal_form_used_def SET (security_invoker = on);
ALTER VIEW public.region_used_def SET (security_invoker = on);
ALTER VIEW public.sector_used_def SET (security_invoker = on);
ALTER VIEW public.statistical_unit_def SET (security_invoker = on);
ALTER VIEW public.statistical_unit_facet_def SET (security_invoker = on);
ALTER VIEW public.timeline_enterprise_def SET (security_invoker = on);
ALTER VIEW public.timeline_establishment_def SET (security_invoker = on);
ALTER VIEW public.timeline_legal_unit_def SET (security_invoker = on);
ALTER VIEW public.timesegments_def SET (security_invoker = on);
ALTER VIEW public.timesegments_years_def SET (security_invoker = on);

-- Other views (7)
ALTER VIEW public.enterprise_external_idents SET (security_invoker = on);
ALTER VIEW public.external_ident_type_active SET (security_invoker = on);
ALTER VIEW public.external_ident_type_ordered SET (security_invoker = on);
ALTER VIEW public.relative_period_with_time SET (security_invoker = on);
ALTER VIEW public.stat_definition_active SET (security_invoker = on);
ALTER VIEW public.stat_definition_ordered SET (security_invoker = on);
ALTER VIEW public.time_context SET (security_invoker = on);

END;
