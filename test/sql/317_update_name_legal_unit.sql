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

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/demo/regions_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_317_lu_era',
    'Import Legal Units Era (317_legal_unit_update.sql)',
    'Import job for legal units from test/data/03_norwegian-legal-units-over-time.csv using legal_unit_source_dates definition.',
    'Test data load (317_legal_unit_update.sql)';

\echo "User uploads the legal units over time (via import job: import_317_lu_era)"
\copy public.import_317_lu_era_upload(stat_ident,name,birth_date,primary_activity_category_code,legal_form_code,sector_code,valid_from,valid_to) FROM 'test/data/316_legal_unit_updates.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Inspecting import job data for import_317_lu_era"
SELECT row_id, state, errors, stat_ident_raw, name_raw, data_source_code_raw, merge_status
FROM public.import_317_lu_era_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_317_lu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_317_lu_era_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_317_lu_era'
ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking legal unit"

SELECT name, valid_from, valid_to
 FROM legal_unit
 ORDER BY valid_from;

SELECT category_id, valid_from, valid_to
 FROM activity
 ORDER BY  valid_from;

SAVEPOINT before_update_on_name;

\echo "Update name for exact same dates as first activity row"
UPDATE legal_unit__for_portion_of_valid
 SET name = 'EQUATOR SOLUTIONS', valid_from = '2023-01-01', valid_to = '2024-12-31'
 WHERE id = (SELECT id FROM public.legal_unit WHERE name = 'EQUATOR GLOBE SOLUTIONS');


\echo "Checking legal unit after update"

-- SELECT *
SELECT name, valid_from, valid_to
 FROM legal_unit
 ORDER BY valid_from;

ROLLBACK TO SAVEPOINT before_update_on_name;


SELECT name, valid_from, valid_to
 FROM legal_unit
 ORDER BY valid_from;

ROLLBACK;
