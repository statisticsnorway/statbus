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
\copy public.activity_category_available_custom(path,name,description) FROM 'samples/norway/activity_category/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'samples/norway/regions/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.region;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.sector_available;

SELECT code, name, active, custom FROM public.data_source_available;
\echo "User uploads the sample data sources"
\copy public.data_source_custom(code,name) FROM 'test/data/02_norwegian_data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code, name, active, custom FROM public.data_source_available;
SELECT count(*) FROM public.data_source_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;
\echo "User uploads establishments without legal_unit"
\copy public.import_establishment_current_without_legal_unit(tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,data_source_code) FROM 'test/data/02_norwegian-establishments-without-legal-unit.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

\x
SELECT unit_type, name, external_idents, data_source_codes, stats, jsonb_pretty(stats_summary) AS stats_summary
FROM statistical_unit ORDER BY name, unit_type;

\echo "Checking statistics"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_pretty(jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL)) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

\i test/rollback_unless_persist_is_specified.sql
