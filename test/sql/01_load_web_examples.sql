BEGIN;

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.super@statbus.org');

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

SELECT standard_code
     , code
     , path
     , parent_path
     , label
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'samples/norway/regions/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , level
     , label
     , code
     , name
 FROM public.region
 ORDER BY path;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
 FROM public.legal_form_available
 ORDER BY code COLLATE "nb-NO-x-icu";

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , name
     , custom
 FROM public.sector_available;


\echo "User uploads the sample data sources"
\copy public.data_source_custom(code,name) FROM 'test/data/01_norwegian_data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
FROM public.data_source_available;

\echo "Supress invalid code warnings, they are tested later, and the debug output contains the current date, that changes with time."
SET client_min_messages TO error;

SELECT COUNT(DISTINCT id) FROM public.legal_unit;
\echo "User uploads the sample legal units"
\copy public.import_legal_unit_current(tax_ident,name,birth_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'samples/norway/legal_unit/enheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT COUNT(DISTINCT id) FROM public.legal_unit;

SELECT COUNT(DISTINCT id) FROM public.establishment;
\echo "User uploads the sample establishments"
\copy public.import_establishment_current_for_legal_unit(tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees) FROM 'samples/norway/establishment/underenheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT COUNT(DISTINCT id) FROM public.establishment;

\echo "Supress invalid code warnings, they are tested later, and the debug output contains the current date, that changes with time."
SET client_min_messages TO warning;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

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

SAVEPOINT before_reset;

\a
\echo "Checking that reset works"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'data'::public.reset_scope) - 'statistical_unit_refresh_now') AS reset_data;
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'getting-started'::public.reset_scope) - 'statistical_unit_refresh_now') AS reset_getting_started;
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope) - 'statistical_unit_refresh_now') AS reset_all;
\a

ROLLBACK TO SAVEPOINT before_reset;

\i test/rollback_unless_persist_is_specified.sql
