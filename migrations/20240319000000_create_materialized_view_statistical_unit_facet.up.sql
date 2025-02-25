BEGIN;

CREATE VIEW public.statistical_unit_facet_def AS
SELECT valid_from
     , valid_to
     , unit_type
     , physical_region_path
     , primary_activity_category_path
     , sector_path
     , legal_form_id
     , physical_country_id
     , status_id
     , count(*) AS count
     , public.jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
FROM public.statistical_unit
WHERE include_unit_in_reports
GROUP BY valid_from
       , valid_to
       , unit_type
       , physical_region_path
       , primary_activity_category_path
       , sector_path
       , legal_form_id
       , physical_country_id
       , status_id;

CREATE UNLOGGED TABLE public.statistical_unit_facet AS
SELECT * FROM public.statistical_unit_facet_def;

CREATE FUNCTION public.statistical_unit_facet_derive(
  valid_after date DEFAULT '-infinity'::date,
  valid_to date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_facet_derive$
DECLARE
  derived_valid_from DATE := (statistical_unit_facet_derive.valid_after + '1 DAY'::INTERVAL)::DATE;
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(valid_after=%, valid_to=%)', valid_after, valid_to;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE daterange(suf.valid_from, suf.valid_to, '[]') &&
          daterange(derived_valid_from,
                    statistical_unit_facet_derive.valid_to, '[]');
      
    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE daterange(sufd.valid_from, sufd.valid_to, '[]') &&
          daterange(derived_valid_from,
                    statistical_unit_facet_derive.valid_to, '[]');
END;
$statistical_unit_facet_derive$;

END;
