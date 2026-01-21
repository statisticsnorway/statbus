BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_341_lu_idents',
    'Import Legal Units duplicate Idents (341_duplicate_tax_ident_big_file.sql)',
    'Import job for legal units from test/data/341_duplicate_tax_ident_big_file.csv using legal_unit_job_provided definition.',
    'Test data load (341_duplicate_tax_ident_big_file.sql)',
    'r_year_curr';

\echo "User uploads the legal units over time (via import job: import_341_lu_idents)"
\copy public.import_341_lu_idents_upload(name,stat_ident,tax_ident) FROM 'test/data/341_duplicate_tax_ident_big_file.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

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

\echo "Inspecting import job data for import_341_lu_idents"
SELECT row_id, state, errors, stat_ident_raw, name_raw, tax_ident_raw, merge_status
FROM public.import_341_lu_idents_data
WHERE tax_ident_raw = '01'
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_341_lu_idents"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_341_lu_idents_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_341_lu_idents'
ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking legal units"

SELECT name, external_idents, unit_type
 FROM statistical_unit
 WHERE unit_type = 'legal_unit'
 ORDER BY external_idents->>'stat_ident';

ROLLBACK;
