BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to load establishments without legal units"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

SELECT code, name, active, custom FROM public.data_source_available;

\i samples/norway/getting-started.sql

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

SELECT count(*) FROM public.activity_category_available;

SELECT count(*) FROM public.region;

SELECT count(*) FROM public.legal_form_available;

SELECT count(*) FROM public.sector_available;

SELECT count(*) FROM public.data_source_available;

SELECT code, name, active, custom FROM public.data_source_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Establishments Without Legal Unit
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_job_provided'),
    'import_02_eswlu_tc',
    'Import Establishments Without LU (02_load_establishment_without_legal_unit.sql)',
    'Import job for establishments from test/data/02_norwegian-establishments-without-legal-unit.csv using establishment_without_lu_job_provided definition.',
    'Test data load (02_load_establishment_without_legal_unit.sql)',
    'r_year_curr';

\echo "User uploads establishments without legal_unit (via import job: import_02_eswlu_tc)"
\copy public.import_02_eswlu_tc_upload(tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,data_source_code) FROM 'test/data/02_norwegian-establishments-without-legal-unit.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Inspecting import job data for import_02_eswlu_tc"
SELECT row_id, state, errors, tax_ident_raw, name_raw, data_source_code_raw, merge_status
FROM public.import_02_eswlu_tc_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_02_eswlu_tc"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_02_eswlu_tc_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_02_eswlu_tc'
ORDER BY slug;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\x
SELECT unit_type, name, external_idents, data_source_codes, stats, jsonb_pretty(stats_summary) AS stats_summary
FROM statistical_unit ORDER BY name, unit_type;

\echo "Checking statistics"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_pretty(jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL)) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

\i test/rollback_unless_persist_is_specified.sql
