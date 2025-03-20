BEGIN;

-- Create a function to disable RLS on import tables to support the \copy command.
-- and that requires privileges, make it a security definer, such that it can be
-- called by the user the tests run as.
CREATE PROCEDURE public.disable_rls_on_table(schema_name text, table_name text) LANGUAGE plpgsql SECURITY DEFINER AS $disable_rls_on_table$
BEGIN
  EXECUTE format('ALTER TABLE %I DISABLE ROW LEVEL SECURITY', table_name);
END;
$disable_rls_on_table$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON PROCEDURE public.disable_rls_on_table TO authenticated;


\i test/setup.sql

-- Display all import definitions with their mappings
SELECT
    id.slug AS import_definition_slug,
    id.name AS import_name,
    it.schema_name AS target_schema_name,
    it.table_name AS data_table_name,
    id.note AS import_note,
    isc.column_name AS source_column,
    itc.column_name AS target_column,
    im.source_expression,
    im.source_value,
    isc.priority AS source_column_priority
FROM public.import_definition id
JOIN public.import_target it ON id.target_id = it.id
LEFT JOIN public.import_mapping im ON id.id = im.definition_id
LEFT JOIN public.import_source_column isc ON im.source_column_id = isc.id
LEFT JOIN public.import_target_column itc ON im.target_column_id = itc.id
ORDER BY id.slug, isc.priority NULLS LAST;

CALL test.set_user_from_email('test.super@statbus.org');

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

SELECT d.slug,
       d.name,
       t.table_name as target_table,
       d.note,
       ds.code as data_source,
       d.time_context_ident,
       d.draft,
       d.valid,
       d.validation_error
FROM public.import_definition d
JOIN public.import_target t ON t.id = d.target_id
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id
WHERE d.slug = 'brreg_hovedenhet_2024';

SELECT d.slug,
       d.name,
       t.table_name as target_table,
       d.note,
       ds.code as data_source,
       d.time_context_ident,
       d.draft,
       d.valid,
       d.validation_error
FROM public.import_definition d
JOIN public.import_target t ON t.id = d.target_id
LEFT JOIN public.data_source ds ON ds.id = d.data_source_id
WHERE d.slug = 'brreg_underenhet_2024';

-- Per year jobs for hovedenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2015 History', 'This job handles the import of BRREG Hovedenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2016 History', 'This job handles the import of BRREG Hovedenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2017 History', 'This job handles the import of BRREG Hovedenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2018 History', 'This job handles the import of BRREG Hovedenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

-- Per year jobs for underenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2015 History', 'This job handles the import of BRREG Underenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2016 History', 'This job handles the import of BRREG Underenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2017 History', 'This job handles the import of BRREG Underenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2018 History', 'This job handles the import of BRREG Underenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

-- Verify that snapshot tables were created
SELECT slug, import_information_snapshot_table_name
FROM public.import_job
ORDER BY id;

-- Verify that the snapshot tables exist in the database
SELECT ij.slug, ij.import_information_snapshot_table_name,
       CASE WHEN EXISTS (
           SELECT 1 FROM pg_tables
           WHERE schemaname = 'public' AND tablename = ij.import_information_snapshot_table_name
       ) THEN 'exists' ELSE 'missing' END AS table_status
FROM public.import_job ij
ORDER BY ij.id;

\echo Verify the concrete tables of one import job
\d public.import_lu_2015_h_upload
\d public.import_lu_2015_h_data
\d public.import_lu_2015_h_import_information

\d public.import_es_2015_h_upload
\d public.import_es_2015_h_data
\d public.import_es_2015_h_import_information

SELECT import_job_slug, import_definition_slug, import_name, import_note, target_schema_name, upload_table_name, data_table_name, source_column, source_value, source_expression, target_column, target_type, uniquely_identifying, source_column_priority
FROM public.import_lu_2015_h_import_information;

\echo Review public.import_information for ensure it matches import_lu_2015_h_import_information_snapshot
SELECT import_job_slug, import_definition_slug, import_name, import_note, target_schema_name, upload_table_name, data_table_name, source_column, source_value, source_expression, target_column, target_type, uniquely_identifying, source_column_priority
FROM public.import_information
WHERE import_job_slug = 'import_lu_2015_h';

-- Disable RLS on import tables to support \copy
CALL public.disable_rls_on_table('public','import_lu_2015_h_upload');
CALL public.disable_rls_on_table('public','import_lu_2016_h_upload');
CALL public.disable_rls_on_table('public','import_lu_2017_h_upload');
CALL public.disable_rls_on_table('public','import_lu_2018_h_upload');
--
CALL public.disable_rls_on_table('public','import_es_2015_h_upload');
CALL public.disable_rls_on_table('public','import_es_2016_h_upload');
CALL public.disable_rls_on_table('public','import_es_2017_h_upload');
CALL public.disable_rls_on_table('public','import_es_2018_h_upload');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.statbus_user_with_email_and_role WHERE id = user_id) AS user_email
FROM public.import_job
WHERE slug = 'import_lu_2015_h';

\echo "Loading historical units"

\copy public.import_lu_2015_h_upload FROM 'samples/norway/history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2016_h_upload FROM 'samples/norway/history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2017_h_upload FROM 'samples/norway/history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2018_h_upload FROM 'samples/norway/history/2018-enheter.csv' WITH CSV HEADER;
\copy public.import_es_2015_h_upload FROM 'samples/norway/history/2015-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2016_h_upload FROM 'samples/norway/history/2016-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2017_h_upload FROM 'samples/norway/history/2017-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2018_h_upload FROM 'samples/norway/history/2018-underenheter.csv' WITH CSV HEADER;

\echo Check import job state before import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state before import
SELECT state, count(*) FROM public.import_lu_2015_h_data GROUP BY state;

\echo Check data row state before import
SELECT state, count(*) FROM public.import_es_2015_h_data GROUP BY state;

\echo Run worker processing to run import jobs and generate computed data
-- Notice that 'WARNING:  Could not find primary_activity_category_code' is expected due to data quality issues, but should not hinder the import process.
-- Notice that only the import job tasks are executed, to avoid ongoing recalculation of computed data
CALL worker.process_tasks(p_queue => 'import');

\echo Check the states of the import job tasks.
select queue,t.command,state,error from worker.tasks as t join worker.command_registry as c on t.command = c.command where t.command = 'import_job_process' order by priority;
select slug, state, error is not null as failed,total_rows,imported_rows, import_completed_pct from public.import_job order by id;

\echo Check import job state after import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state after import
SELECT state, count(*) FROM public.import_lu_2015_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2016_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2017_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2018_h_data GROUP BY state;

SELECT state, count(*) FROM public.import_es_2015_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2016_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2017_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2018_h_data GROUP BY state;

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

-- Once the Imports are finished, then all the analytics can be processed, but only once.
CALL worker.process_tasks(p_queue => 'analytics');

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo Run any remaining tasks, there should be none.
CALL worker.process_tasks();

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo Overview of statistical units, but not details, there are too many units.
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, name, external_idents ->> 'tax_ident', unit_type, unit_id;

\o tmp/51_import_jobs_for_norway_history-timepoints.log
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
\o tmp/51_import_jobs_for_norway_history-timesegments_def.log
EXPLAIN ANALYZE SELECT * FROM public.timesegments_def;
\o tmp/51_import_jobs_for_norway_history-timeline_establishment_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment_def;
\o tmp/51_import_jobs_for_norway_history-timeline_legal_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit_def;
\o tmp/51_import_jobs_for_norway_history-timeline_enterprise_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise_def;
\o tmp/51_import_jobs_for_norway_history-statistical_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
\o

ROLLBACK;
