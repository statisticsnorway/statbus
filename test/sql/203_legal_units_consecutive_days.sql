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

-- Create Import Job for Legal Units (Day 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_day1',
    'Import LU Day 1 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-1.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Day 1 - via import job: import_43_lu_day1)"
\copy public.import_43_lu_day1_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-1.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Day 1)
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Day 1)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks (Day 1)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking related table counts after Day 1 analytics"
SELECT
    (SELECT COUNT(*) FROM public.location) AS location_count,
    (SELECT COUNT(*) FROM public.contact) AS contact_count,
    (SELECT COUNT(*) FROM public.activity) AS activity_count;

\echo "Checking timeline_legal_unit data after Day 1 load"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;

-- Create Import Job for Legal Units (Day 4)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_day4',
    'Import LU Day 4 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-4.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Day 4 - via import job: import_43_lu_day4)"
\copy public.import_43_lu_day4_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-4.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Day 4)
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Day 4)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks (Day 4)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking related table counts after Day 4 analytics"
SELECT
    (SELECT COUNT(*) FROM public.location) AS location_count,
    (SELECT COUNT(*) FROM public.contact) AS contact_count,
    (SELECT COUNT(*) FROM public.activity) AS activity_count;

\echo "Checking timeline_legal_unit data after Day 4 load"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;

-- Create Import Job for Legal Units (Day 3)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_day3',
    'Import LU Day 3 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-3.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Day 3 - via import job: import_43_lu_day3)"
\copy public.import_43_lu_day3_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-3.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Day 3)
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Day 3)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks (Day 3)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking related table counts after Day 3 analytics"
SELECT
    (SELECT COUNT(*) FROM public.location) AS location_count,
    (SELECT COUNT(*) FROM public.contact) AS contact_count,
    (SELECT COUNT(*) FROM public.activity) AS activity_count;

\echo "Checking timeline_legal_unit data after Day 3 load"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;

ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Scenario 2 - Day 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_s2_day1',
    'Import LU Scenario 2 Day 1 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-1.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Scenario 2 - Day 1 - via import job: import_43_lu_s2_day1)"
\copy public.import_43_lu_s2_day1_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-1.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Scenario 2 - Day 1)
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Scenario 2 - Day 1)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Scenario 2 - Day 3)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_s2_day3',
    'Import LU Scenario 2 Day 3 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-3.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Scenario 2 - Day 3 - via import job: import_43_lu_s2_day3)"
\copy public.import_43_lu_s2_day3_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-3.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Scenario 2 - Day 3)
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Scenario 2 - Day 3)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks (Scenario 2 - Day 1 & 3)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking related table counts after Scenario 2 (Day 1 & 3) analytics"
SELECT
    (SELECT COUNT(*) FROM public.location) AS location_count,
    (SELECT COUNT(*) FROM public.contact) AS contact_count,
    (SELECT COUNT(*) FROM public.activity) AS activity_count;

\echo "Checking timeline_legal_unit data after Scenario 2 (Day 1 & 3) load"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;

-- Create Import Job for Legal Units (Scenario 2 - Day 4)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_43_lu_s2_day4',
    'Import LU Scenario 2 Day 4 (43_legal_units_consecutive_days.sql)',
    'Import job for test/data/43_legal-units-day-4.csv.',
    'Test data load (43_legal_units_consecutive_days.sql)';
\echo "User uploads the legal units over time (Scenario 2 - Day 4 - via import job: import_43_lu_s2_day4)"
\copy public.import_43_lu_s2_day4_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-4.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs (Scenario 2 - Day 4)
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing (Scenario 2 - Day 4)"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks (Scenario 2 - Day 1, 3 & 4)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking related table counts after Scenario 2 (Day 1, 3 & 4) analytics"
SELECT
    (SELECT COUNT(*) FROM public.location) AS location_count,
    (SELECT COUNT(*) FROM public.contact) AS contact_count,
    (SELECT COUNT(*) FROM public.activity) AS activity_count;

\echo "Checking timeline_legal_unit data after Scenario 2 (Day 1, 3 & 4) load"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;

ROLLBACK;
