BEGIN;

-- Remove security_invoker setting from views
ALTER VIEW public.activity_category_used_def RESET (security_invoker);
ALTER VIEW public.country_used_def RESET (security_invoker);
ALTER VIEW public.data_source_used_def RESET (security_invoker);
ALTER VIEW public.legal_form_used_def RESET (security_invoker);
ALTER VIEW public.region_used_def RESET (security_invoker);
ALTER VIEW public.sector_used_def RESET (security_invoker);
ALTER VIEW public.statistical_unit_def RESET (security_invoker);
ALTER VIEW public.statistical_unit_facet_def RESET (security_invoker);
ALTER VIEW public.timeline_enterprise_def RESET (security_invoker);
ALTER VIEW public.timeline_establishment_def RESET (security_invoker);
ALTER VIEW public.timeline_legal_unit_def RESET (security_invoker);
ALTER VIEW public.timesegments_def RESET (security_invoker);
ALTER VIEW public.timesegments_years_def RESET (security_invoker);

ALTER VIEW public.enterprise_external_idents RESET (security_invoker);
ALTER VIEW public.external_ident_type_active RESET (security_invoker);
ALTER VIEW public.external_ident_type_ordered RESET (security_invoker);
ALTER VIEW public.relative_period_with_time RESET (security_invoker);
ALTER VIEW public.stat_definition_active RESET (security_invoker);
ALTER VIEW public.stat_definition_ordered RESET (security_invoker);
ALTER VIEW public.time_context RESET (security_invoker);

END;
