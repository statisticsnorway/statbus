BEGIN;

\echo "Setting up Statbus to load legal_unit without establishment with statistics"
\echo "This is the use case for Morocco, so sample data from them"

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id, only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'isic_v4'
ON CONFLICT (only_one_setting)
DO UPDATE SET
    activity_category_standard_id = EXCLUDED.activity_category_standard_id;

SELECT activity_category_standard_id FROM public.settings;

\echo "User uploads the activity categories"
\copy public.activity_category_available_custom(path,name,description) FROM 'test/data/04_morocco-activity_category.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

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
\copy public.import_legal_unit_current(stat_ident,name,birth_date,legal_form_code,physical_postal_place,physical_address_part1,primary_activity_category_code,physical_country_iso_2,physical_region_code,sector_code,employees,turnover) FROM 'test/data/04_morocco-legal-units-with-stats-small.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

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
