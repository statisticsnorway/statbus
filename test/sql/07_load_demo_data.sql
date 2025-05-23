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

-- Create Import Job for Legal Units (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_current_year'),
    'import_07_lu_curr_b1',
    'Import LU Demo CSV B1 (07_load_demo_data.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample legal units (via import job: import_07_lu_curr_b1)"
\copy public.import_07_lu_curr_b1_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_current_year'),
    'import_07_esflu_curr_b1',
    'Import Formal ES Demo CSV B1 (07_load_demo_data.sql)',
    'Import job for app/public/demo/formal_establishments_units_demo.csv using establishment_for_lu_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample formal establishments (via import job: import_07_esflu_curr_b1)"
\copy public.import_07_esflu_curr_b1_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_current_year'),
    'import_07_eswlu_curr_b1',
    'Import Informal ES Demo CSV B1 (07_load_demo_data.sql)',
    'Import job for app/public/demo/informal_establishments_units_demo.csv using establishment_without_lu_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample informal establishments (via import job: import_07_eswlu_curr_b1)"
\copy public.import_07_eswlu_curr_b1_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 1
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 1"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_07_%_b1' ORDER BY slug;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks - Block 1
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

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

-- Create Import Job for Legal Units (Demo CSV, Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_current_year'),
    'import_07_lu_curr_b2',
    'Import LU Demo CSV B2 (07_load_demo_data.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample legal units (via import job: import_07_lu_curr_b2)"
\copy public.import_07_lu_curr_b2_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV, Block 2)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_current_year'),
    'import_07_esflu_curr_b2',
    'Import Formal ES Demo CSV B2 (07_load_demo_data.sql)',
    'Import job for app/public/demo/formal_establishments_units_demo.csv using establishment_for_lu_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample formal establishments (via import job: import_07_esflu_curr_b2)"
\copy public.import_07_esflu_curr_b2_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 2
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 2"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_07_%_b2' ORDER BY slug;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks - Block 2
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

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

-- Create Import Job for Legal Units (Demo CSV, Block 3)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_current_year'),
    'import_07_lu_curr_b3',
    'Import LU Demo CSV B3 (07_load_demo_data.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample legal units (via import job: import_07_lu_curr_b3)"
\copy public.import_07_lu_curr_b3_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 3
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 3"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_07_%_b3' ORDER BY slug;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks - Block 3
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

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

-- Create Import Job for Informal Establishments (Demo CSV, Block 4)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_current_year'),
    'import_07_eswlu_curr_b4',
    'Import Informal ES Demo CSV B4 (07_load_demo_data.sql)',
    'Import job for app/public/demo/informal_establishments_units_demo.csv using establishment_without_lu_current_year definition.',
    'Test data load (07_load_demo_data.sql)';
\echo "User uploads the sample informal establishments (via import job: import_07_eswlu_curr_b4)"
\copy public.import_07_eswlu_curr_b4_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs - Block 4
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Block 4"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_07_%_b4' ORDER BY slug;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks - Block 4
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

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
