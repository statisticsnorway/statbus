BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to load legal_unit without establishment with statistics"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.super@statbus.org');

\echo "This is the use case for Morocco, so sample data from them"

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id, only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'isic_v4'
ON CONFLICT (only_one_setting)
DO UPDATE SET
    activity_category_standard_id = EXCLUDED.activity_category_standard_id;

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\echo "User uploads the activity categories"
\copy public.activity_category_available_custom(path,name,description) FROM 'test/data/04_morocco-activity_category.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

SELECT standard_code
     , code
     , path
     , parent_path
     , label
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;

\echo "User uploads the regions"
\copy public.region_upload(path, name) FROM 'test/data/04_morocco-regions.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.region;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'test/data/04_morocco-legal_form.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'test/data/04_morocco-sector.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.sector_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;
\echo "User uploads legal_units with statistics"
\copy public.import_legal_unit_current(stat_ident,legal_form_code,name,birth_date,physical_postplace,physical_address_part1,primary_activity_category_code,physical_country_iso_2,physical_region_code,sector_code,employees,turnover) FROM 'test/data/04_morocco-legal-units-with-stats-small.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_batch() GROUP BY success;


\x
SELECT unit_type, name, external_idents, stats, jsonb_pretty(stats_summary) AS stats_summary
FROM statistical_unit
ORDER BY name, unit_type;

\echo "Checking statistics"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_pretty(jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL)) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

ROLLBACK;
