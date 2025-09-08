BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to load legal_unit without establishment with statistics"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id, only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'nace_v2.1'
ON CONFLICT (only_one_setting)
DO UPDATE SET
    activity_category_standard_id = EXCLUDED.activity_category_standard_id;

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name,description) FROM 'samples/norway/activity_category/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

SELECT standard_code
     , code
     , path
     , parent_path
     , label
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'samples/norway/regions/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.region;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.sector_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units with Statistics
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_04_lu_tc_stats',
    'Import Legal Units with Stats (04_legal_units_with_statistics.sql)',
    'Import job for legal units from test/data/04_legal-units-with-stats.csv using legal_unit_job_provided definition.',
    'Test data load (04_legal_units_with_statistics.sql)',
    'r_year_curr';

\echo "User uploads legal_units with statistics (via import job: import_04_lu_tc_stats)"
\copy public.import_04_lu_tc_stats_upload(tax_ident,name,birth_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postplace,postal_postcode,postal_region_code,postal_country_iso_2,primary_activity_category_code,sector_code,legal_form_code,employees,turnover) FROM 'test/data/04_legal-units-with-stats.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Inspecting import job data for import_04_lu_tc_stats"
SELECT row_id, state, errors, tax_ident, name, employees, turnover, merge_statuses
FROM public.import_04_lu_tc_stats_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_04_lu_tc_stats"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_04_lu_tc_stats_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_04_lu_tc_stats'
ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\x
SELECT unit_type, name, external_idents, stats, jsonb_pretty(stats_summary) AS stats_summary
FROM statistical_unit
ORDER BY name, unit_type;

\echo "Checking statistics"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_pretty(jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL)) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

ROLLBACK;
