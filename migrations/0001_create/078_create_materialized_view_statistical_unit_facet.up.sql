BEGIN;

\echo public.statistical_unit_facet
CREATE MATERIALIZED VIEW public.statistical_unit_facet AS
SELECT valid_from
     , valid_to
     , unit_type
     , physical_region_path
     , primary_activity_category_path
     , sector_path
     , legal_form_id
     , physical_country_id
     , count(*) AS count
     , public.jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
FROM public.statistical_unit
GROUP BY valid_from
       , valid_to
       , unit_type
       , physical_region_path
       , primary_activity_category_path
       , sector_path
       , legal_form_id
       , physical_country_id
;

END;