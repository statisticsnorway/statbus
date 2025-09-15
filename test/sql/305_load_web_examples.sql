BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

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
SELECT path
     , level
     , label
     , code
     , name
 FROM public.region
 ORDER BY path;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
 FROM public.legal_form_available
 ORDER BY code COLLATE "nb-NO-x-icu";

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT path
     , name
     , custom
 FROM public.sector_available;


\echo "User uploads the sample data sources"
\copy public.data_source_custom(code,name) FROM 'test/data/01_norwegian_data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT code
     , name
     , custom
FROM public.data_source_available;

\echo "Supress invalid code warnings, they are tested later, and the debug output contains the current date, that changes with time."

-- Create Import Job for Legal Units (Web Example)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_lu_web_example_current',
    'Import Legal Units - Web Example (Current Year)',
    'Import job for legal units from samples/norway/legal_unit/enheter-selection-web-import.csv using legal_unit_job_provided definition.',
    'Test data load (01_load_web_examples.sql)',
    'r_year_curr';

\echo "User uploads the sample legal units (via import job: import_lu_web_example_current)"
\copy public.import_lu_web_example_current_upload(tax_ident,name,birth_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'samples/norway/legal_unit/enheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Establishments (Web Example)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_es_web_example_current',
    'Import Establishments - Web Example (Current Year)',
    'Import job for establishments from samples/norway/establishment/underenheter-selection-web-import.csv using establishment_for_lu_job_provided definition.',
    'Test data load (01_load_web_examples.sql)',
    'r_year_curr';

\echo "User uploads the sample establishments (via import job: import_es_web_example_current)"
\copy public.import_es_web_example_current_upload(tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees) FROM 'samples/norway/establishment/underenheter-selection-web-import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- SET client_min_messages TO DEBUG1;
\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;
-- SET client_min_messages TO NOTICE;

\echo "Inspecting first 5 rows of legal unit import job data (import_lu_web_example_current_data)"
SELECT row_id, state, errors, invalid_codes, tax_ident_raw, name_raw, birth_date_raw, physical_address_part1_raw, primary_activity_category_code_raw, merge_status
FROM public.import_lu_web_example_current_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job statuses"
SELECT ij.slug,
       ij.state,
       ij.time_context_ident,
       ij.total_rows,
       ij.imported_rows,
       ij.error IS NOT NULL AS has_error,
       CASE ij.slug
           WHEN 'import_lu_web_example_current' THEN
               (SELECT COUNT(*) FROM public.import_lu_web_example_current_data dr WHERE dr.state = 'error')
           WHEN 'import_es_web_example_current' THEN
               (SELECT COUNT(*) FROM public.import_es_web_example_current_data dr WHERE dr.state = 'error')
           ELSE NULL -- Should not happen with the WHERE clause below
       END AS error_rows
FROM public.import_job AS ij
WHERE ij.slug IN ('import_lu_web_example_current', 'import_es_web_example_current') ORDER BY ij.slug;

\echo "Error rows in import_lu_web_example_current_data (if any):"
SELECT row_id, state, errors, tax_ident_raw, name_raw, merge_status
FROM public.import_lu_web_example_current_data
WHERE (errors IS NOT NULL AND errors IS DISTINCT FROM '{}'::JSONB) OR state = 'error'
ORDER BY row_id;

\echo "Legal unit import data with invalid_codes (if any):"
SELECT row_id, state, errors, invalid_codes, merge_status, tax_ident_raw, name_raw
FROM public.import_lu_web_example_current_data
WHERE invalid_codes IS NOT NULL AND invalid_codes <> '{}'::JSONB
ORDER BY row_id;

\echo "Error rows in import_es_web_example_current_data (if any):"
SELECT row_id, state, errors, tax_ident_raw, legal_unit_tax_ident_raw, name_raw, merge_status
FROM public.import_es_web_example_current_data
WHERE (errors IS NOT NULL AND errors IS DISTINCT FROM '{}'::JSONB) OR state = 'error'
ORDER BY row_id;

\echo "Establishment import data with invalid_codes (if any):"
SELECT row_id, state, errors, invalid_codes, merge_status, tax_ident_raw, name_raw
FROM public.import_es_web_example_current_data
WHERE invalid_codes IS NOT NULL AND invalid_codes <> '{}'::JSONB
ORDER BY row_id;

\echo "Checking counts of imported units"
SELECT 'legal_unit' AS unit_type, COUNT(DISTINCT id) AS count FROM public.legal_unit
UNION ALL
SELECT 'establishment' AS unit_type, COUNT(DISTINCT id) AS count FROM public.establishment;

\echo "Worker task summary after import processing"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking statistics"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL AND invalid_codes <> '{}'::JSONB) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

SAVEPOINT before_reset;

\a
\echo "Checking that reset works"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'data'::public.reset_scope)) AS reset_data;
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'getting-started'::public.reset_scope)) AS reset_getting_started;
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope)) AS reset_all;
\a

ROLLBACK TO SAVEPOINT before_reset;

\i test/rollback_unless_persist_is_specified.sql
