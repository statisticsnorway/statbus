SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to test enterprise grouping and primary"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

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

\echo "Test births at the start of the year"

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Block 1 - Births Start of Year)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_41_lu_era_b1_birth_start_y',
    'Import LU Era B1 Births Start Year (41_history_legal_units_births.sql)',
    'Import job for test/data/41_legal-units-births-start-of-year.csv.',
    'Test data load (41_history_legal_units_births.sql)';
\echo "User uploads the legal units (via import job: import_41_lu_era_b1_birth_start_y)"
\copy public.import_41_lu_era_b1_birth_start_y_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/41_legal-units-births-start-of-year.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 1
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_41_lu_era_b1_birth_start_y"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_41_lu_era_b1_birth_start_y_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_41_lu_era_b1_birth_start_y'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 1
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, birth_date, death_date
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;

\echo "Check statistical unit history by year - births should be 1 for year 2010 and 2011"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
AND unit_type = 'legal_unit';


\echo "Check statistical unit history by year-month - births should be 1 for year-month 2010-1 and 2011-1"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit';


\x


ROLLBACK TO before_loading_units;

\echo "Test births at the start of the second month"

\x
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Block 2 - Births Start of Second Month)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_41_lu_era_b2_birth_start_m2',
    'Import LU Era B2 Births Start M2 (41_history_legal_units_births.sql)',
    'Import job for test/data/41_legal-units-births-start-of-second-month.csv.',
    'Test data load (41_history_legal_units_births.sql)';
\echo "User uploads the legal units (via import job: import_41_lu_era_b2_birth_start_m2)"
\copy public.import_41_lu_era_b2_birth_start_m2_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/41_legal-units-births-start-of-second-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 2
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_41_lu_era_b2_birth_start_m2"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_41_lu_era_b2_birth_start_m2_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_41_lu_era_b2_birth_start_m2'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 2
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, birth_date, death_date
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;

\echo "Check statistical unit history by year - births should be 1 for year 2010 and 2011"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
AND unit_type = 'legal_unit';


\echo "Check statistical unit history by year-month - births should be 1 for year-month 2010-2 and 2011-2"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit';


\x

ROLLBACK TO before_loading_units;

\echo "Test births in the middle of a month"

\x
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Block 3 - Births Middle of Month)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_41_lu_era_b3_birth_mid_m',
    'Import LU Era B3 Births Mid-Month (41_history_legal_units_births.sql)',
    'Import job for test/data/41_legal-units-births-middle-of-month.csv.',
    'Test data load (41_history_legal_units_births.sql)';
\echo "User uploads the legal units (via import job: import_41_lu_era_b3_birth_mid_m)"
\copy public.import_41_lu_era_b3_birth_mid_m_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/41_legal-units-births-middle-of-month.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 3
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for import_41_lu_era_b3_birth_mid_m"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_41_lu_era_b3_birth_mid_m_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_41_lu_era_b3_birth_mid_m'
ORDER BY slug;

\echo Run worker processing for analytics tasks - Block 3
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Check legal units over time"
SELECT external_idents ->> 'tax_ident' as tax_ident, name, valid_after, valid_from, valid_to, birth_date, death_date
FROM public.statistical_unit
WHERE unit_type = 'legal_unit'
ORDER BY external_idents ->> 'tax_ident', valid_from;

\echo "Check statistical unit history by year - births should be 1 for year 2010 and 2011"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
AND unit_type = 'legal_unit';


\echo "Check statistical unit history by year-month - births should be 1 for year-month 2010-1 and 2011-1"
SELECT resolution, year, month, unit_type, count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year-month'
AND year < 2013
AND unit_type = 'legal_unit';

\x

ROLLBACK;
