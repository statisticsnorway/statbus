DROP TABLE IF EXISTS public.sample_frame;
DROP TABLE IF EXISTS public.report_tree;
DROP TABLE IF EXISTS public.postal_index;
DROP TABLE IF EXISTS public.analysis_log;
DROP TABLE IF EXISTS public.custom_analysis_check;
DROP TABLE IF EXISTS public.analysis_queue;

DROP VIEW public.legal_unit_brreg_view;
DROP FUNCTION admin.legal_unit_brreg_view_upsert();

DROP VIEW public.establishment_brreg_view;
DROP FUNCTION admin.upsert_establishment_brreg_view();

DROP VIEW public.region_7_levels_view;
DROP FUNCTION admin.upsert_region_7_levels();
