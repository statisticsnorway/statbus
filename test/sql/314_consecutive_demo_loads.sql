BEGIN;

\i test/setup.sql

-- Reset sequences for stable IDs in this test
ALTER TABLE public.legal_unit ALTER COLUMN id RESTART WITH 1;
ALTER TABLE public.establishment ALTER COLUMN id RESTART WITH 1;
ALTER TABLE public.enterprise ALTER COLUMN id RESTART WITH 1;

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

\echo ""
\echo "---"
\echo "Phase 1: Load initial demo data (simple, current time context)"
\echo "---"

-- Create Import Job for Legal Units (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_314_lu_curr_p1',
    'Import LU Demo CSV B1 (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_job_provided definition.',
    'Test data load (314_consecutive_demo_loads.sql)',
    'r_year_curr';
\echo "User uploads the sample legal units (via import job: import_314_lu_curr_p1)"
\copy public.import_314_lu_curr_p1_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_314_esflu_curr_p1',
    'Import Formal ES Demo CSV B1 (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/formal_establishments_units_demo.csv using establishment_for_lu_job_provided definition.',
    'Test data load (314_consecutive_demo_loads.sql)',
    'r_year_curr';
\echo "User uploads the sample formal establishments (via import job: import_314_esflu_curr_p1)"
\copy public.import_314_esflu_curr_p1_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV, Block 1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_job_provided'),
    'import_314_eswlu_curr_p1',
    'Import Informal ES Demo CSV B1 (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/informal_establishments_units_demo.csv using establishment_without_lu_job_provided definition.',
    'Test data load (314_consecutive_demo_loads.sql)',
    'r_year_curr';
\echo "User uploads the sample informal establishments (via import job: import_314_eswlu_curr_p1)"
\copy public.import_314_eswlu_curr_p1_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Phase 1"
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Phase 1"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_314_%_p1' ORDER BY slug;

\echo "Unit counts after Phase 1"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo ""
\echo "---"
\echo "Phase 2: Load data with source dates, which will now trigger UPDATE operations"
\echo "---"

-- Create Import Job for Legal Units (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_314_lu_wsd_p2',
    'Import LU Demo CSV w/ dates (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv using legal_unit_source_dates definition.',
    'Test data load (314_consecutive_demo_loads.sql)';
\echo "User uploads the sample legal units with source dates (via import job: import_314_lu_wsd_p2)"
\copy public.import_314_lu_wsd_p2_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for LU source dates job"
CALL worker.process_tasks(p_queue => 'import');
\echo "Checking LU source dates job status"
\x
SELECT
    slug,
    state,
    analysis_completed_pct,
    import_completed_pct,
    total_rows,
    imported_rows,
    jsonb_pretty(error::jsonb) AS error
FROM public.import_job WHERE slug = 'import_314_lu_wsd_p2';
\x

\echo "Inspecting LU source dates data table for skipped/error rows"
\x
SELECT row_id, state, action, operation, legal_unit_id, enterprise_id, errors, merge_status
FROM public.import_314_lu_wsd_p2_data WHERE action = 'skip' OR state = 'error' ORDER BY row_id;
\x

-- Create Import Job for Formal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_314_esflu_wsd_p2',
    'Import Formal ES Demo CSV w/ dates (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/formal_establishments_units_with_source_dates_demo.csv using establishment_for_lu_source_dates definition.',
    'Test data load (314_consecutive_demo_loads.sql)';
\echo "User uploads the sample formal establishments with source dates (via import job: import_314_esflu_wsd_p2)"
\copy public.import_314_esflu_wsd_p2_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for Formal ES source dates job"
CALL worker.process_tasks(p_queue => 'import');
\echo "Checking Formal ES source dates job status"
\x
SELECT
    slug,
    state,
    analysis_completed_pct,
    import_completed_pct,
    total_rows,
    imported_rows,
    jsonb_pretty(error::jsonb) AS error
FROM public.import_job WHERE slug = 'import_314_esflu_wsd_p2';
\x

\echo "Inspecting Formal ES source dates data table for skipped/error rows"
\x
SELECT row_id, state, action, operation, legal_unit_id, establishment_id, errors, merge_status FROM public.import_314_esflu_wsd_p2_data WHERE action = 'skip' OR state = 'error' ORDER BY row_id;
\x

-- Create Import Job for Informal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_314_eswlu_wsd_p2',
    'Import Informal ES Demo CSV w/ dates (314_consecutive_demo_loads.sql)',
    'Import job for app/public/demo/informal_establishments_units_with_source_dates_demo.csv using establishment_without_lu_source_dates definition.',
    'Test data load (314_consecutive_demo_loads.sql)';
\echo "User uploads the sample informal establishments with source dates (via import job: import_314_eswlu_wsd_p2)"
\copy public.import_314_eswlu_wsd_p2_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,physical_country_iso_2,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,unit_size_code,status_code,physical_latitude,physical_longitude,physical_altitude) FROM 'app/public/demo/informal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for Informal ES source dates job"
CALL worker.process_tasks(p_queue => 'import');
\echo "Checking Informal ES source dates job status"
\x
SELECT
    slug,
    state,
    analysis_completed_pct,
    import_completed_pct,
    total_rows,
    imported_rows,
    error
FROM public.import_job WHERE slug = 'import_314_eswlu_wsd_p2';
\x

\echo "Inspecting Informal ES source dates data table for skipped/error rows"
\x
SELECT row_id, state, action, operation, establishment_id, errors, merge_status FROM public.import_314_eswlu_wsd_p2_data WHERE action = 'skip' OR state = 'error' ORDER BY row_id;
\x

\echo "Unit counts after Phase 2"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Final check of worker queue to ensure no tasks are stuck"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Final check of import job progress and completion status"
\x
SELECT
    slug,
    state,
    analysis_completed_pct,
    completed_analysis_steps_weighted,
    total_analysis_steps_weighted,
    import_completed_pct,
    total_rows,
    imported_rows,
    jsonb_pretty(error::jsonb) AS error
FROM public.import_job
WHERE slug LIKE 'import_314_%'
ORDER BY slug;
\x


\i test/rollback_unless_persist_is_specified.sql
