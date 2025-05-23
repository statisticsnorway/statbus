BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'isic_v4'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'isic_v4')
   WHERE settings.id = EXCLUDED.id;
;

\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name) FROM 'app/public/demo/activity_custom_isic_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/demo/regions_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/demo/legal_forms_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/demo/sectors_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Same external ident for legal unit and establishment"

-- Create Import Job for Legal Units (Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'), -- Corrected slug
    'import_31_lu_era_b1',
    'Import LU Era B1 (31_load_units_errors.sql)',
    'Import job for test/data/31_legal_units.csv (Block 1).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads legal units (via import job: import_31_lu_era_b1)"
\copy public.import_31_lu_era_b1_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/31_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Block 1 - Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_explicit_dates'), -- Corrected slug
    'import_31_esflu_era_b1',
    'Import Formal ES Era B1 Errors (31_load_units_errors.sql)',
    'Import job for test/data/31_formal_establishments_errors.csv (Block 1).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads formal establishments with same stat_ident as legal units (via import job: import_31_esflu_era_b1)"
\copy public.import_31_esflu_era_b1_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'test/data/31_formal_establishments_errors.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 1
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 1"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b1_data dr WHERE dr.state = 'error') AS lu_error_rows,
       (SELECT COUNT(*) FROM public.import_31_esflu_era_b1_data dr WHERE dr.state = 'error') AS es_error_rows
FROM public.import_job
WHERE slug IN ('import_31_lu_era_b1', 'import_31_esflu_era_b1') ORDER BY slug;

\echo "Error rows in import_31_esflu_era_b1_data (if any):"
SELECT row_id, state, error, tax_ident, stat_ident, name
FROM public.import_31_esflu_era_b1_data
WHERE error IS NOT NULL OR state = 'error'
ORDER BY row_id;

\echo Run worker processing for analytics tasks - Block 1 (errors primarily tested on import queue)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Same external ident for formal establishment and informal establishment"

-- Create Import Job for Legal Units (Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'), -- Corrected slug
    'import_31_lu_era_b2',
    'Import LU Era B2 (31_load_units_errors.sql)',
    'Import job for test/data/31_legal_units.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads legal units (via import job: import_31_lu_era_b2)"
\copy public.import_31_lu_era_b2_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/31_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_explicit_dates'), -- Corrected slug
    'import_31_esflu_era_b2',
    'Import Formal ES Era B2 (31_load_units_errors.sql)',
    'Import job for test/data/31_formal_establishments.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads formal establishments (via import job: import_31_esflu_era_b2)"
\copy public.import_31_esflu_era_b2_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'test/data/31_formal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Block 2 - Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_explicit_dates'), -- Corrected slug
    'import_31_eswlu_era_b2_errors',
    'Import Informal ES Era B2 Errors (31_load_units_errors.sql)',
    'Import job for test/data/31_informal_establishments_errors.csv (Block 2).',
    'Test data load (31_load_units_errors.sql)';
\echo "User uploads informal establishments with same stat_idents as formal establishments (via import job: import_31_eswlu_era_b2_errors)"
\copy public.import_31_eswlu_era_b2_errors_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'test/data/31_informal_establishments_errors.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 2
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Checking import job statuses for Block 2"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b2_data dr WHERE dr.state = 'error') AS lu_error_rows,
       (SELECT COUNT(*) FROM public.import_31_esflu_era_b2_data dr WHERE dr.state = 'error') AS es_formal_error_rows,
       (SELECT COUNT(*) FROM public.import_31_eswlu_era_b2_errors_data dr WHERE dr.state = 'error') AS es_informal_error_rows
FROM public.import_job
WHERE slug IN ('import_31_lu_era_b2', 'import_31_esflu_era_b2', 'import_31_eswlu_era_b2_errors') ORDER BY slug;

\echo "Error rows in import_31_eswlu_era_b2_errors_data (if any):"
SELECT row_id, state, error, tax_ident, stat_ident, name
FROM public.import_31_eswlu_era_b2_errors_data
WHERE error IS NOT NULL OR state = 'error'
ORDER BY row_id;

\echo Run worker processing for analytics tasks - Block 2 (errors primarily tested on import queue)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo "User uploads legal units with invalid latitude"
-- Create Import Job for Legal Units (Block 3 - Coordinate Errors)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'), -- Corrected slug
    'import_31_lu_era_b3_coord_errors',
    'Import LU Era B3 Coord Errors (31_load_units_errors.sql)',
    'Import job for test/data/31_legal_units_with_coordinates_errors.csv (Block 3).',
    'Test data load (31_load_units_errors.sql)';
\copy public.import_31_lu_era_b3_coord_errors_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code, physical_latitude, physical_longitude, physical_altitude, web_address, email_address, phone_number) FROM 'test/data/31_legal_units_with_coordinates_errors.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 3
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job status for Block 3 (import_31_lu_era_b3_coord_errors)"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_31_lu_era_b3_coord_errors_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_31_lu_era_b3_coord_errors';

\echo "Error rows in import_31_lu_era_b3_coord_errors_data (if any):"
SELECT row_id, state, error, tax_ident, name, physical_latitude
FROM public.import_31_lu_era_b3_coord_errors_data
WHERE error IS NOT NULL OR state = 'error'
ORDER BY row_id;

\echo Run worker processing for analytics tasks - Block 3 (errors primarily tested on import queue)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

ROLLBACK;
