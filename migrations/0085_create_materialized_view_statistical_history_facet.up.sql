\echo public.statistical_history_facet
CREATE MATERIALIZED VIEW public.statistical_history_facet AS
SELECT * FROM public.statistical_history_facet_def
ORDER BY year, month;