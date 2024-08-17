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
SELECT activity_category_standard_id FROM public.settings;

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


\echo "Checking timepoints."
SELECT tp.unit_type
     , public.get_external_idents(tp.unit_type, tp.unit_id)->0->'tax_ident' AS tax_ident
     , tp.timepoint
FROM public.timepoints AS tp
ORDER BY unit_type;

\echo "Checking timesegments"
SELECT ts.unit_type
     , public.get_external_idents(ts.unit_type, ts.unit_id)->0->'tax_ident' AS tax_ident
     , ts.valid_after
     , ts.valid_to
FROM public.timesegments AS ts
ORDER BY unit_type;


\echo "Checking timeline_establishment data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->0->'tax_ident' AS tax_ident
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
     , public.get_external_idents(unit_type, unit_id)->0->'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , stats
FROM public.timeline_establishment
ORDER BY unit_type, unit_id, valid_after, valid_to;

\echo "Checking timeline_legal_unit data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->0->'tax_ident' AS tax_ident
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
     , public.get_external_idents(unit_type, unit_id)->0->'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , stats
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;
\x

\x
\echo "Checking statistical_unit"
SELECT unit_type
     , external_idents
     , invalid_codes
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < '2020-12-31'::DATE AND '2020-12-31'::DATE <= valid_to
 ORDER BY unit_type;

-- TODO: Fix enterprise.stats_summary

\echo "Checking statistical_unit totals"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < '2020-12-31'::DATE AND '2020-12-31'::DATE <= valid_to
 GROUP BY unit_type;

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
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE type = 'year'
ORDER BY year,unit_type;

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
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE type = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

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
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE type = 'year'
ORDER BY year,unit_type;

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
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE type = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;
\x


\a
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type,
          'year'::public.statistical_history_type,
          NULL::INTEGER,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          'enterprise'::public.statistical_unit_type,
          'year'::public.statistical_history_type,
          2020,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::public.ltree,
          NULL::INTEGER,
          NULL::INTEGER
     ))) AS statistical_history_drilldown;

\echo "Test statistical_unit_hierarchy"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921838309'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy('enterprise',(SELECT unit_id FROM selected_enterprise))
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

ROLLBACK;
