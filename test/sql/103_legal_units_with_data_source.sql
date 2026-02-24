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

-- Create Import Job for Legal Units with Data Source
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_32_lu_tc_ds',
    'Import LU with Time Context and Data Source (32_legal_units_with_data_source.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_job_provided definition.',
    'Test data load (32_legal_units_with_data_source.sql)',
    'r_year_curr';

\echo "User uploads the sample legal units (via import job: import_32_lu_tc_ds)"
\copy public.import_32_lu_tc_ds_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

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

\echo "Inspecting import job data for import_32_lu_tc_ds"
SELECT row_id, state, errors, tax_ident_raw, name_raw, data_source_code_raw, merge_status
FROM public.import_32_lu_tc_ds_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_32_lu_tc_ds"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_32_lu_tc_ds_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_32_lu_tc_ds'
ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking statistics"

SELECT name, external_idents, unit_type, data_source_codes, primary_activity_category_path, web_address, stats_summary->'employees'->>'value_int' AS employees, stats_summary->'turnover'->>'value_int' AS turnover
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 ORDER BY name, external_idents->>'tax_ident', unit_type, valid_from, unit_id;

\i test/rollback_unless_persist_is_specified.sql
