BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

ALTER TABLE public.import_job ALTER COLUMN id RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

SELECT standard_code
     , code
     , path
     , parent_path
     , label
     , name
FROM public.activity_category_available
ORDER BY standard_code, path;

SELECT path
     , level
     , label
     , code
     , name
 FROM public.region
 ORDER BY path;

SELECT code
     , name
     , custom
 FROM public.legal_form_available
 ORDER BY code COLLATE "nb-NO-x-icu";

SELECT path
     , name
     , custom
 FROM public.sector_available;

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
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

\echo "Testing import job clone"
-- Clone legal unit job
SELECT id AS lu_job_id FROM public.import_job WHERE slug = 'import_lu_web_example_current' \gset
SELECT slug, description, note, time_context_ident, default_valid_from, default_valid_to, default_data_source_code, upload_table_name, data_table_name, priority, analysis_batch_size, processing_batch_size   , analysis_completed_pct , analysis_rows_per_sec , current_step_code , current_step_priority , max_analysis_priority , total_analysis_steps_weighted , completed_analysis_steps_weighted     , total_rows , imported_rows , import_completed_pct , import_rows_per_sec , last_progress_update , state        , error , review, edit_comment FROM public.import_job_clone(:lu_job_id, 'import_lu_clone');

-- Clone establishment job
SELECT id AS es_job_id FROM public.import_job WHERE slug = 'import_es_web_example_current' \gset
SELECT slug, description, note, time_context_ident, default_valid_from, default_valid_to, default_data_source_code, upload_table_name, data_table_name, priority, analysis_batch_size, processing_batch_size   , analysis_completed_pct , analysis_rows_per_sec , current_step_code , current_step_priority , max_analysis_priority , total_analysis_steps_weighted , completed_analysis_steps_weighted     , total_rows , imported_rows , import_completed_pct , import_rows_per_sec , last_progress_update , state        , error , review, edit_comment FROM public.import_job_clone(:es_job_id, 'import_es_clone');

-- SET client_min_messages TO DEBUG1;
\echo Run worker processing for import job clone
SELECT COALESCE(max(id), 0) as max_task_id FROM worker.tasks \gset
CALL worker.process_tasks(p_queue => 'import');
\echo "Checking new worker tasks for cloned jobs"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE t.id > :max_task_id GROUP BY queue,state ORDER BY queue,state;
-- SET client_min_messages TO NOTICE;

\echo "Comparing upload table contents between original and cloned jobs"
SELECT
    (SELECT upload_table_name FROM public.import_job WHERE slug = 'import_lu_web_example_current') AS original_lu_upload_table,
    (SELECT upload_table_name FROM public.import_job WHERE slug = 'import_lu_clone') AS cloned_lu_upload_table,
    (SELECT upload_table_name FROM public.import_job WHERE slug = 'import_es_web_example_current') AS original_es_upload_table,
    (SELECT upload_table_name FROM public.import_job WHERE slug = 'import_es_clone') AS cloned_es_upload_table
\gset

\echo " -> LU upload table diff (should be 0)"
SELECT COUNT(*) FROM (
    TABLE public.:"original_lu_upload_table"
    EXCEPT
    TABLE public.:"cloned_lu_upload_table"
) AS t;

\echo " -> ES upload table diff (should be 0)"
SELECT COUNT(*) FROM (
    TABLE public.:"original_es_upload_table"
    EXCEPT
    TABLE public.:"cloned_es_upload_table"
) AS t;

\echo "Checking import job statuses for cloned jobs"
SELECT ij.slug,
       ij.state,
       ij.time_context_ident,
       ij.total_rows,
       ij.imported_rows,
       ij.error IS NOT NULL AS has_error,
       CASE ij.slug
           WHEN 'import_lu_clone' THEN
               (SELECT COUNT(*) FROM public.import_lu_clone_data dr WHERE dr.state = 'error')
           WHEN 'import_es_clone' THEN
               (SELECT COUNT(*) FROM public.import_es_clone_data dr WHERE dr.state = 'error')
           ELSE NULL
       END AS error_rows
FROM public.import_job AS ij
WHERE ij.slug IN ('import_lu_clone', 'import_es_clone') ORDER BY ij.slug;


SAVEPOINT before_reset;

\a
\echo "Checking that reset works"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'units'::public.reset_scope)) AS reset_unit;
ROLLBACK TO SAVEPOINT before_reset;

SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'data'::public.reset_scope)) AS reset_data;
ROLLBACK TO SAVEPOINT before_reset;

SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'data'::public.reset_scope)) AS reset_data;
ROLLBACK TO SAVEPOINT before_reset;

SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'getting-started'::public.reset_scope)) AS reset_getting_started;
ROLLBACK TO SAVEPOINT before_reset;

SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope)) AS reset_all;
ROLLBACK TO SAVEPOINT before_reset;
\a


\i test/rollback_unless_persist_is_specified.sql
