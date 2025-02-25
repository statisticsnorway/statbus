BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.super@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'isic_v4'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'isic_v4')
   WHERE settings.id = EXCLUDED.id;
;
SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;
\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name) FROM 'app/public/demo/activity_custom_isic_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT standard_code
     , code
     , path
     , parent_path
     , label
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;
\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/demo/regions_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , level
     , label
     , code
     , name
 FROM public.region
 ORDER BY path;
\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/demo/legal_forms_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
 FROM public.legal_form_available
 ORDER BY code COLLATE "nb-NO-x-icu";
\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/demo/sectors_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , name
     , custom
 FROM public.sector_available;

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the sample legal units"
\copy public.import_legal_unit_current(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\echo "User uploads the sample formal establishments"
\copy public.import_establishment_current_for_legal_unit(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\echo "User uploads the sample informal establishments"
\copy public.import_establishment_current_without_legal_unit(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_batch() GROUP BY success;

\echo "Checking statistics"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < CURRENT_DATE AND CURRENT_DATE <= valid_to
 GROUP BY unit_type;
\x


ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the sample legal units"
\copy public.import_legal_unit_current(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\echo "User uploads the sample formal establishments"
\copy public.import_establishment_current_for_legal_unit(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_batch() GROUP BY success;

\echo "Checking statistics"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < CURRENT_DATE AND CURRENT_DATE <= valid_to
 GROUP BY unit_type;
\x


ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the sample legal units"
\copy public.import_legal_unit_current(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_batch() GROUP BY success;

\echo "Checking statistics"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < CURRENT_DATE AND CURRENT_DATE <= valid_to
 GROUP BY unit_type;
\x



ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the sample informal establishments"
\copy public.import_establishment_current_without_legal_unit(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing to generate computed data
SELECT success, count(*) FROM worker.process_batch() GROUP BY success;

\echo "Checking statistics"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_after < CURRENT_DATE AND CURRENT_DATE <= valid_to
 GROUP BY unit_type;
\x

ROLLBACK;
