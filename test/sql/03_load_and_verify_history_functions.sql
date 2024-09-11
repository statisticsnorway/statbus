SET datestyle TO 'ISO, DMY';

BEGIN;

\echo "Setting up Statbus to load establishments without legal units"

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'nace_v2.1'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
   WHERE settings.id = EXCLUDED.id;
;
SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name,description) FROM 'app/public/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.region;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.sector_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/03_norwegian-legal-units-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the establishments over time"
\copy public.import_establishment_era_for_legal_unit(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover) FROM 'test/data/03_norwegian-establishments-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

\echo "Checking statistical_history_periods"
SELECT * FROM public.statistical_history_periods
-- Only list previous years, so the test is stable over time.
WHERE year <= 2023;


\echo "Checking timepoints."
SELECT tp.unit_type
     , COALESCE
          ( public.get_external_idents(tp.unit_type, tp.unit_id)->>'tax_ident'
          , eei.external_idents->>'tax_ident'
          ) AS tax_ident
     , tp.timepoint
FROM public.timepoints AS tp
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = tp.unit_type
      AND eei.unit_id = tp.unit_id
      AND eei.valid_after <= tp.timepoint AND tp.timepoint <= eei.valid_to
ORDER BY tp.unit_type, tp.timepoint, tp.unit_id;

\echo "Checking timesegments."
SELECT ts.unit_type
     , COALESCE
          ( public.get_external_idents(ts.unit_type, ts.unit_id)->>'tax_ident'
          , eei.external_idents->>'tax_ident'
          ) AS tax_ident
     , ts.valid_after
     , ts.valid_to
FROM public.timesegments AS ts
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = ts.unit_type
      AND eei.unit_id = ts.unit_id
      AND eei.valid_after <= ts.valid_after AND ts.valid_to <= eei.valid_to
ORDER BY ts.unit_type, ts.valid_after, ts.unit_id;


\echo "Checking timeline_establishment data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , secondary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , legal_form_code
     , legal_form_name
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_path
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_path
     , postal_country_iso_2
     , invalid_codes
FROM public.timeline_establishment
ORDER BY unit_type, unit_id, valid_after, valid_to;


\echo "Checking timeline_establishment stats"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , stats
FROM public.timeline_establishment
ORDER BY unit_type, unit_id, valid_after, valid_to;

\echo "Checking timeline_legal_unit data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , secondary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , legal_form_code
     , legal_form_name
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postal_code
     , physical_postal_place
     , physical_region_path
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postal_code
     , postal_postal_place
     , postal_region_path
     , postal_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;


\x
\echo "Checking timeline_legal_unit stats"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , stats
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;
\x


\echo "Checking timeline_enterprise data"
SELECT te.unit_type
     , eei.external_idents->>'tax_ident' AS tax_ident
     , te.valid_after
     , te.valid_from
     , te.valid_to
     , te.name
     , te.birth_date
     , te.death_date
     , te.search
     , te.primary_activity_category_path
     , te.secondary_activity_category_path
     , te.activity_category_paths
     , te.sector_path
     , te.sector_code
     , te.sector_name
     , te.legal_form_code
     , te.legal_form_name
     , te.physical_address_part1
     , te.physical_address_part2
     , te.physical_address_part3
     , te.physical_postal_code
     , te.physical_postal_place
     , te.physical_region_path
     , te.physical_country_iso_2
     , te.postal_address_part1
     , te.postal_address_part2
     , te.postal_address_part3
     , te.postal_postal_code
     , te.postal_postal_place
     , te.postal_region_path
     , te.postal_country_iso_2
     , te.invalid_codes
FROM public.timeline_enterprise AS te
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = te.unit_type
      AND eei.unit_id = te.unit_id
      AND daterange(eei.valid_after, eei.valid_to, '(]')
       && daterange(te.valid_after, te.valid_to, '(]')
ORDER BY te.unit_type, te.unit_id, te.valid_after, te.valid_to;


\x
\echo "Checking timeline_enterprise stats"
SELECT te.unit_type
     , eei.external_idents->>'tax_ident' AS tax_ident
     , te.valid_after
     , te.valid_from
     , te.valid_to
     , te.name
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.timeline_enterprise AS te
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = te.unit_type
      AND eei.unit_id = te.unit_id
      AND daterange(eei.valid_after, eei.valid_to, '(]') 
       && daterange(te.valid_after, te.valid_to, '(]')
ORDER BY te.unit_type, te.unit_id, te.valid_after, te.valid_to;
\x


\x
\echo "Check statistical_unit"
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'stats'
          -'stats_summary'
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY valid_after, valid_from, valid_to, unit_type, unit_id;

\echo "Checking statistical_unit totals"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

\echo "Test over the years"

\echo "Verify the generation of ranges"
SELECT * FROM public.statistical_history_periods
-- Only list previous years, so the test is stable over time.
WHERE year <= 2023;

\echo "Test yearly data"
SELECT year
     , unit_type
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history
WHERE resolution = 'year'
ORDER BY year,unit_type;

\echo "Test yearly stats"
SELECT year
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE resolution = 'year'
ORDER BY year,unit_type;

\echo "Test monthly data for 2019"
SELECT year, month
     , unit_type
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly stats for 2019"
SELECT year, month
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\x
\echo "Inspect facet summary table"
SELECT valid_from
     , valid_to
     , unit_type
     , physical_region_path
     , primary_activity_category_path
     , sector_path
     , count
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.statistical_unit_facet
  ORDER BY valid_from, valid_to, unit_type
;
\x

\echo "Test yearly facet data"
SELECT year
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history_facet
WHERE resolution = 'year'
ORDER BY year,unit_type;

\echo "Test yearly facet stats"
SELECT year
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE resolution = 'year'
ORDER BY year,unit_type;

\echo "Test monthly facet data"
SELECT year, month
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history_facet
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly facet data"
SELECT year, month
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\a
\echo "Test yearly drilldown - enterprise"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type,
          'year'::public.history_resolution,
          NULL::INTEGER,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - legal_unit"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'legal_unit'::public.statistical_unit_type,
          'year'::public.history_resolution,
          NULL::INTEGER,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - establishment"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'establishment'::public.statistical_unit_type,
          'year'::public.history_resolution,
          NULL::INTEGER,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - enterprise - with all filters as top level"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type, -- unit_type
          'year'::public.history_resolution, -- resolution
          2019, -- year
          '11'::public.ltree, -- region_path
          'H'::public.ltree, -- activity_category_path
          'innl'::public.ltree, -- sector_path
          (SELECT id FROM public.legal_form WHERE code = 'AS'), -- legal_form_id
          (SELECT id FROM public.country WHERE iso_2 = 'NO') -- country_id
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - enterprise - with all filters as bottom level"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type, -- unit_type
          'year'::public.history_resolution, -- resolution
          2019, -- year
          '11.21'::public.ltree, -- region_path
          'H.49.4.1.0'::public.ltree, -- activity_category_path
          'innl.a_ikke_fin.2100'::public.ltree, -- sector_path
          (SELECT id FROM public.legal_form WHERE code = 'AS'), -- legal_form_id
          (SELECT id FROM public.country WHERE iso_2 = 'NO') -- country_id
     ))) AS statistical_history_drilldown;


\echo "Test monthly drilldown"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type,
          'year-month'::public.history_resolution,
          2019,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

\echo "Test statistical_unit_hierarchy - For a date when it does not exist"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                '2013-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

\echo "Test statistical_unit_hierarchy - For a date when it does exist"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                '2010-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

WITH selected_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
        AND unit_type = 'legal_unit'
    LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy('legal_unit',(SELECT unit_id FROM selected_legal_unit))
          )
     ) AS statistical_unit_hierarchy;

WITH selected_establishment AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '895406732'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy('establishment',(SELECT unit_id FROM selected_establishment))
          )
     ) AS statistical_unit_hierarchy;
\a

\x
\echo "Check relevant_statistical_units"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.relevant_statistical_units(
     'enterprise',
     (SELECT unit_id FROM selected_enterprise),
     '2023-01-01'::DATE
);


ROLLBACK;
