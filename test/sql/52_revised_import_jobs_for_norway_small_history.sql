-- Test suite for the revised import_job system using Norway small history data.
-- This test verifies the multi-target, batch-oriented import process.
BEGIN;

-- The disable_rls_on_table procedure should exist from previous tests/migrations.
-- Verify its existence just in case.
SELECT proname FROM pg_proc WHERE proname = 'disable_rls_on_table' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

\i test/setup.sql

-- Verify the default import definitions exist (created by migration)
\echo Verify default import definitions
SELECT slug, name, note, time_context_ident, operation_type, draft, valid
FROM public.import_definition
WHERE slug IN ('legal_unit_explicit_dates', 'establishment_for_lu_explicit_dates')
ORDER BY slug;

-- Set user context for creating jobs
CALL test.set_user_from_email('test.admin@statbus.org');

-- Create Import Jobs using explicit date definitions
\echo Create import jobs for legal units (explicit dates)
WITH def AS (SELECT id FROM public.import_definition where slug = 'legal_unit_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_lu_2015_sht_revised', 'Revised Import Job for Legal Units 2015 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'legal_unit_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_lu_2016_sht_revised', 'Revised Import Job for Legal Units 2016 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'legal_unit_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_lu_2017_sht_revised', 'Revised Import Job for Legal Units 2017 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'legal_unit_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_lu_2018_sht_revised', 'Revised Import Job for Legal Units 2018 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

\echo Create import jobs for establishments (explicit dates)
WITH def AS (SELECT id FROM public.import_definition where slug = 'establishment_for_lu_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_es_2015_sht_revised', 'Revised Import Job for Establishments 2015 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'establishment_for_lu_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_es_2016_sht_revised', 'Revised Import Job for Establishments 2016 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'establishment_for_lu_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_es_2017_sht_revised', 'Revised Import Job for Establishments 2017 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

WITH def AS (SELECT id FROM public.import_definition where slug = 'establishment_for_lu_explicit_dates')
INSERT INTO public.import_job (definition_id, slug, description, note)
SELECT def.id, 'import_es_2018_sht_revised', 'Revised Import Job for Establishments 2018 Small History Test', 'Uses explicit dates definition.' FROM def RETURNING slug, description, note, upload_table_name, data_table_name, state; -- snapshot_table_name removed

-- Verify that snapshot column exists and is populated
\echo Verify definition_snapshot column
SELECT slug, definition_snapshot IS NOT NULL as snapshot_exists, jsonb_typeof(definition_snapshot) as snapshot_type
FROM public.import_job
WHERE slug LIKE '%_sht_revised'
ORDER BY id;

-- Verify the concrete tables of one import job pair
\echo Verify concrete tables for one job pair
\d public.import_lu_2015_sht_revised_upload
\d public.import_lu_2015_sht_revised_data
-- Snapshot table no longer exists

\d public.import_es_2015_sht_revised_upload
\d public.import_es_2015_sht_revised_data
-- Snapshot table no longer exists

-- Review snapshot content for one job
\echo Review snapshot content for import_lu_2015_sht_revised
SELECT jsonb_pretty(definition_snapshot->'import_definition') as import_definition,
       jsonb_pretty(definition_snapshot->'import_step_list') as import_step_list,
       jsonb_pretty(definition_snapshot->'import_data_column_list') as import_data_column_list,
       jsonb_pretty(definition_snapshot->'import_source_column_list') as import_source_column_list,
       jsonb_pretty(definition_snapshot->'import_mapping_list') as import_mapping_list
FROM public.import_job
WHERE slug = 'import_lu_2015_sht_revised';

-- Disable RLS on upload tables to support \copy
\echo Disable RLS on upload tables
CALL public.disable_rls_on_table('public','import_lu_2015_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_lu_2016_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_lu_2017_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_lu_2018_sht_revised_upload');
--
CALL public.disable_rls_on_table('public','import_es_2015_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_es_2016_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_es_2017_sht_revised_upload');
CALL public.disable_rls_on_table('public','import_es_2018_sht_revised_upload');

\echo "Setting up Statbus for Norway (if not already done)"
\i samples/norway/getting-started.sql

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM auth.user WHERE id = user_id) AS user_email -- Use auth.users
FROM public.import_job
WHERE slug = 'import_lu_2015_sht_revised';

\echo "Loading historical units into _upload tables"
-- Use the same source files, but map valid_from/valid_to explicitly
\copy public.import_lu_2015_sht_revised_upload (tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, legal_form_code, valid_from, valid_to) FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2016_sht_revised_upload (tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, legal_form_code, valid_from, valid_to) FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2017_sht_revised_upload (tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, legal_form_code, valid_from, valid_to) FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2018_sht_revised_upload (tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, legal_form_code, valid_from, valid_to) FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
-- establishment_tax_ident is now handled dynamically via external_ident_type 'tax_ident'
\copy public.import_es_2015_sht_revised_upload (tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, valid_from, valid_to) FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2016_sht_revised_upload (tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, valid_from, valid_to) FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2017_sht_revised_upload (tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, valid_from, valid_to) FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2018_sht_revised_upload (tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, primary_activity_category_code, sector_code, unit_size_code, status_code, data_source_code, valid_from, valid_to) FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;

-- Check import job state after upload (should be 'upload_completed')
\echo Check import job state after upload
SELECT slug, state, total_rows FROM import_job WHERE slug LIKE '%_sht_revised' ORDER BY id;

-- Check data row state before processing (should not exist yet)
\echo Check data row state before processing
SELECT 'import_lu_2015_sht_revised_data' as table_name, state, count(*) FROM public.import_lu_2015_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2016_sht_revised_data' as table_name, state, count(*) FROM public.import_lu_2016_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2017_sht_revised_data' as table_name, state, count(*) FROM public.import_lu_2017_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2018_sht_revised_data' as table_name, state, count(*) FROM public.import_lu_2018_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2015_sht_revised_data' as table_name, state, count(*) FROM public.import_es_2015_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2016_sht_revised_data' as table_name, state, count(*) FROM public.import_es_2016_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2017_sht_revised_data' as table_name, state, count(*) FROM public.import_es_2017_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2018_sht_revised_data' as table_name, state, count(*) FROM public.import_es_2018_sht_revised_data GROUP BY state;

\echo Run worker processing to run import jobs and generate computed data
CALL worker.process_tasks();
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

-- Check import job state after processing (should be 'finished')
\echo Check import job state after processing
SELECT slug, state, total_rows, imported_rows, error FROM import_job WHERE slug LIKE '%_sht_revised' ORDER BY id;

-- Check data row state after processing (should be 'imported' or 'error')
\echo Check data row state after processing
SELECT 'import_lu_2015_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_lu_2015_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2016_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_lu_2016_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2017_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_lu_2017_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_lu_2018_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_lu_2018_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2015_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_es_2015_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2016_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_es_2016_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2017_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_es_2017_sht_revised_data GROUP BY state UNION ALL
SELECT 'import_es_2018_sht_revised_data' as table_name, state, count(*), MIN(last_completed_priority), MAX(last_completed_priority) FROM public.import_es_2018_sht_revised_data GROUP BY state;

-- Check a few rows in a data table to see intermediate/final IDs
\echo Sample data from import_lu_2015_sht_revised_data
SELECT tax_ident, name, state, last_completed_priority, legal_unit_id, physical_location_id, primary_activity_id, error
FROM public.import_lu_2015_sht_revised_data
LIMIT 5;

\echo Sample data from import_es_2015_sht_revised_data
-- Check resolved IDs and potentially dynamic stat columns if they were added/mapped
SELECT tax_ident, legal_unit_tax_ident, name, state, last_completed_priority, legal_unit_id, establishment_id, physical_location_id, primary_activity_id, contact_id, error -- Add other relevant IDs like stat_for_unit_employees_id if applicable
FROM public.import_es_2015_sht_revised_data
LIMIT 5;

-- Overview of statistical units (should match the old test)
\echo Overview of statistical units
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, name, external_idents ->> 'tax_ident', unit_type, unit_id;


-- Detailed statistical units check (should match the old test)
\echo Getting statistical_units after upload
\x
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          -'stats'
          -'stats_summary'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, unit_type, external_idents ->> 'tax_ident', unit_id;
\x

ROLLBACK;
