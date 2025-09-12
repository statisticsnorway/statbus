BEGIN;

CREATE VIEW public.statistical_unit_facet_def AS
SELECT valid_from
     , valid_to
     , valid_until
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
       , valid_until
       , unit_type
       , physical_region_path
       , primary_activity_category_path
       , sector_path
       , legal_form_id
       , physical_country_id
       , status_id;

CREATE TABLE public.statistical_unit_facet AS
SELECT * FROM public.statistical_unit_facet_def;

CREATE FUNCTION public.statistical_unit_facet_derive(
  valid_from date DEFAULT '-infinity'::date,
  valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_unit_facet_derive$
BEGIN
    RAISE DEBUG 'Running statistical_unit_facet_derive(valid_from=%, valid_until=%)', valid_from, valid_until;
    DELETE FROM public.statistical_unit_facet AS suf
    WHERE from_until_overlaps(suf.valid_from, suf.valid_until,
                          statistical_unit_facet_derive.valid_from,
                          statistical_unit_facet_derive.valid_until);

    INSERT INTO public.statistical_unit_facet
    SELECT * FROM public.statistical_unit_facet_def AS sufd
    WHERE from_until_overlaps(sufd.valid_from, sufd.valid_until,
                          statistical_unit_facet_derive.valid_from,
                          statistical_unit_facet_derive.valid_until);
END;
$statistical_unit_facet_derive$;

END;
