SET datestyle TO 'ISO, DMY';

BEGIN;

\echo "Setting up Statbus to test enterprise grouping and primary"

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

SAVEPOINT before_loading_units;

\echo "Test sector changes in the middle of a month"

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-middle-of-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;

\echo "Test statistical unit history by year - sector_change_count should be 1 for year 2011"
SELECT resolution, year, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;


\echo "Test statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-1"
SELECT resolution, year, month, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;

\x


ROLLBACK TO before_loading_units;

\echo "Test sector changes at the start of the second month"


\x
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-start-of-second-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;


\echo "Check statistical unit history by year - sector_change_count should be 1 for year 2011"
SELECT resolution, year,month, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2012
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;



\echo "Check statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-2"
SELECT resolution, year, month, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2012
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;

\x

ROLLBACK TO before_loading_units;

\echo "Test sector changes at the start of the year"

\x
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-start-of-year.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();


\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;


\echo "Check statistical unit history by year - sector_change_count should be 1 for year 2011 and 2012"
SELECT resolution, year,month, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2014
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;


\echo "Check statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-1 and 2012-1"
SELECT resolution, year, month, unit_type, count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;

\x

ROLLBACK;
