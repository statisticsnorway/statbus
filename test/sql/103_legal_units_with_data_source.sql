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

-- Create Import Job for Legal Units with Data Source
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_current_year'),
    'import_32_lu_curr_ds',
    'Import LU Current with Data Source (32_legal_units_with_data_source.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_current_year definition.',
    'Test data load (32_legal_units_with_data_source.sql)';

\echo "User uploads the sample legal units (via import job: import_32_lu_curr_ds)"
\copy public.import_32_lu_curr_ds_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Inspecting import job data for import_32_lu_curr_ds"
SELECT row_id, state, error, tax_ident, name, data_source_code
FROM public.import_32_lu_curr_ds_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_32_lu_curr_ds"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_32_lu_curr_ds_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_32_lu_curr_ds'
ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking statistics"

SELECT name, external_idents, unit_type, data_source_codes, invalid_codes
 FROM statistical_unit
 WHERE valid_after < CURRENT_DATE AND CURRENT_DATE <= valid_to
 ORDER BY name, external_idents->>'tax_ident', unit_type, valid_from, unit_id;

ROLLBACK;
