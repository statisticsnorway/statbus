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

\i samples/norway/brreg/create-import-definition-legal_unit.sql
\i samples/norway/brreg/create-import-definition-establishment.sql

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
WHERE d.slug = 'brreg_hovedenhet';

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
WHERE d.slug = 'brreg_underenhet';

-- Per year jobs for hovedenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_hovedenhet_2015', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_hovedenhet_2016', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_hovedenhet_2017', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_hovedenhet_2018', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet', 'This job handles the import of BRREG Hovedenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

-- Per year jobs for underenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_underenhet_2015', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet', 'This job handles the import of BRREG Underenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_underenhet_2016', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet', 'This job handles the import of BRREG Underenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_underenhet_2017', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet', 'This job handles the import of BRREG Underenhet data.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, import_information_snapshot_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_underenhet_2018', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet', 'This job handles the import of BRREG Underenhet data.'
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
\d public.import_hovedenhet_2015_upload
\d public.import_hovedenhet_2015_data
\d public.import_hovedenhet_2015_import_information

\d public.import_underenhet_2015_upload
\d public.import_underenhet_2015_data
\d public.import_underenhet_2015_import_information

SELECT import_job_slug, import_definition_slug, import_name, import_note, target_schema_name, upload_table_name, data_table_name, source_column, source_value, source_expression, target_column, target_type, uniquely_identifying, source_column_priority
FROM public.import_hovedenhet_2015_import_information;

\echo Review public.import_information for ensure it matches import_hovedenhet_2015_import_information_snapshot
SELECT import_job_slug, import_definition_slug, import_name, import_note, target_schema_name, upload_table_name, data_table_name, source_column, source_value, source_expression, target_column, target_type, uniquely_identifying, source_column_priority
FROM public.import_information
WHERE import_job_slug = 'import_hovedenhet_2015';

-- Disable RLS on import tables to support \copy
CALL public.disable_rls_on_table('public','import_hovedenhet_2015_upload');
CALL public.disable_rls_on_table('public','import_hovedenhet_2016_upload');
CALL public.disable_rls_on_table('public','import_hovedenhet_2017_upload');
CALL public.disable_rls_on_table('public','import_hovedenhet_2018_upload');
--
CALL public.disable_rls_on_table('public','import_underenhet_2015_upload');
CALL public.disable_rls_on_table('public','import_underenhet_2016_upload');
CALL public.disable_rls_on_table('public','import_underenhet_2017_upload');
CALL public.disable_rls_on_table('public','import_underenhet_2018_upload');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.statbus_user_with_email_and_role WHERE id = user_id) AS user_email
FROM public.import_job
WHERE slug = 'import_hovedenhet_2015';

\echo "Loading historical units"

\copy public.import_hovedenhet_2015_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_hovedenhet_2015';

\copy public.import_hovedenhet_2016_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_hovedenhet_2016';

\copy public.import_hovedenhet_2017_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_hovedenhet_2017';

\copy public.import_hovedenhet_2018_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_hovedenhet_2018';

\copy public.import_underenhet_2015_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_underenhet_2015';

\copy public.import_underenhet_2016_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_underenhet_2016';

\copy public.import_underenhet_2017_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_underenhet_2017';

\copy public.import_underenhet_2018_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;
UPDATE import_job SET state = 'upload_completed' WHERE slug = 'import_underenhet_2018';

\echo Check import job state before import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state before import
SELECT state, count(*) FROM public.import_hovedenhet_2015_data GROUP BY state;

\echo Check data row state before import
SELECT state, count(*) FROM public.import_underenhet_2015_data GROUP BY state;

\echo Run worker processing to run import jobs and generate computed data
SELECT success, count(*) FROM worker.process_tasks() GROUP BY success;

\echo Check import job state after import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state after import
SELECT state, count(*) FROM public.import_hovedenhet_2015_data GROUP BY state;

\echo Check data row state after import
SELECT state, count(*) FROM public.import_underenhet_2015_data GROUP BY state;

\echo Overview of statistical units
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, name, external_idents ->> 'tax_ident', unit_type, unit_id;


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
