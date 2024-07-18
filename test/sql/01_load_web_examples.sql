BEGIN;

\echo "Setting up Statbus using the web provided examples"

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

SELECT standard_code
     , path
     , parent_code
     , label
     , code
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , level
     , label
     , code
     , name
 FROM public.region
 ORDER BY path;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
 FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , name
     , custom
 FROM public.sector_available;

\echo "User uploads the sample legal units"
\copy public.import_legal_unit_current(tax_ident,name,birth_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'app/public/enheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT COUNT(*) FROM public.legal_unit;

\echo "User uploads the sample establishments"
\copy public.import_establishment_current_for_legal_unit(tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees) FROM 'app/public/underenheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT COUNT(*) FROM public.establishment;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

\echo "Checking statistics"
\x
SELECT unit_type
     , count(*)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , sum(employees) AS sum_employees
     , sum(turnover) AS sum_turnover
 FROM statistical_unit
 GROUP BY unit_type;
\x

END;
