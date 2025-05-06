BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Display summary of created definitions
SELECT slug, name, note, time_context_ident, strategy, valid, validation_error
FROM public.import_definition
WHERE slug LIKE 'brreg_%_2024'
ORDER BY slug;

-- Per year jobs for hovedenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2015 History', 'This job handles the import of BRREG Hovedenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2016 History', 'This job handles the import of BRREG Hovedenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2017 History', 'This job handles the import of BRREG Hovedenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2018 History', 'This job handles the import of BRREG Hovedenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

-- Per year jobs for underenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2015 History', 'This job handles the import of BRREG Underenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2016 History', 'This job handles the import of BRREG Underenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2017 History', 'This job handles the import of BRREG Underenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2018 History', 'This job handles the import of BRREG Underenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

\echo Verify the concrete tables of one import job
\d public.import_lu_2015_h_upload
\d public.import_lu_2015_h_data

\d public.import_es_2015_h_upload
\d public.import_es_2015_h_data

-- Display the definition snapshot for one job (optional, can be large)
-- SELECT slug, definition_snapshot FROM public.import_job WHERE slug = 'import_lu_2015_h';

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.user WHERE id = user_id) AS user_email
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

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_lu_2015_h_data GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
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

\echo Check data row state after import (should be 'processed' or 'error')
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

ROLLBACK;
