SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to test enterprise grouping and primary"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SAVEPOINT before_loading_units;

\echo "Test sector changes in the middle of a month"

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Block 1 - Sector Change Mid-Month)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_40_lu_era_b1_sector_mid',
    'Import LU Era B1 Sector Mid-Month (40_history_legal_units_changes_over_time.sql)',
    'Import job for test/data/40_legal-units-sector-change-middle-of-month.csv.',
    'Test data load (40_history_legal_units_changes_over_time.sql)';
\echo "User uploads the legal units (via import job: import_40_lu_era_b1_sector_mid)"
\copy public.import_40_lu_era_b1_sector_mid_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-middle-of-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 1
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_40_lu_era_b1_sector_mid"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_40_lu_era_b1_sector_mid_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_40_lu_era_b1_sector_mid'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 1
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;

\echo "Test statistical unit history by year - sector_change_count should be 1 for year 2011"
SELECT resolution, year, unit_type, countable_count AS count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;


\echo "Test statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-1"
SELECT resolution, year, month, unit_type, countable_count AS count, births, deaths, sector_change_count
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

-- Create Import Job for Legal Units (Block 2 - Sector Change Start of Second Month)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_40_lu_era_b2_sector_start_m2',
    'Import LU Era B2 Sector Start M2 (40_history_legal_units_changes_over_time.sql)',
    'Import job for test/data/40_legal-units-sector-change-start-of-second-month.csv.',
    'Test data load (40_history_legal_units_changes_over_time.sql)';
\echo "User uploads the legal units (via import job: import_40_lu_era_b2_sector_start_m2)"
\copy public.import_40_lu_era_b2_sector_start_m2_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-start-of-second-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 2
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_40_lu_era_b2_sector_start_m2"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_40_lu_era_b2_sector_start_m2_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_40_lu_era_b2_sector_start_m2'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 2
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;


\echo "Check statistical unit history by year - sector_change_count should be 1 for year 2011"
SELECT resolution, year,month, unit_type, countable_count AS count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2012
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;



\echo "Check statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-2"
SELECT resolution, year, month, unit_type, countable_count AS count, births, deaths, sector_change_count
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

-- Create Import Job for Legal Units (Block 3 - Sector Change Start of Year)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_40_lu_era_b3_sector_start_y',
    'Import LU Era B3 Sector Start Year (40_history_legal_units_changes_over_time.sql)',
    'Import job for test/data/40_legal-units-sector-change-start-of-year.csv.',
    'Test data load (40_history_legal_units_changes_over_time.sql)';
\echo "User uploads the legal units (via import job: import_40_lu_era_b3_sector_start_y)"
\copy public.import_40_lu_era_b3_sector_start_y_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/40_legal-units-sector-change-start-of-year.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 3
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_40_lu_era_b3_sector_start_y"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_40_lu_era_b3_sector_start_y_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_40_lu_era_b3_sector_start_y'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 3
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check sector for legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_from, valid_to, sector_code
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;


\echo "Check statistical unit history by year - sector_change_count should be 1 for year 2011 and 2012"
SELECT resolution, year,month, unit_type, countable_count AS count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2014
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;


\echo "Check statistical unit history by year-month - sector_change_count should be 1 for year-month 2011-1 and 2012-1"
SELECT resolution, year, month, unit_type, countable_count AS count, births, deaths, sector_change_count
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit'
ORDER BY resolution, year, month, unit_type;

\x

ROLLBACK;
